# frozen_string_literal: true

require "digest"
require "digest/md5"
require "json"
require "stringio"
require "zlib"

module Logister
  class TelemetryArchiveExporter
    class Error < StandardError
      attr_reader :archive

      def initialize(message, archive: nil)
        @archive = archive
        super(message)
      end
    end

    RECORD_TYPES = {
      "ingest_events" => { model: IngestEvent, timestamp_column: :occurred_at },
      "trace_spans" => { model: TraceSpan, timestamp_column: :started_at }
    }.freeze
    DEFAULT_BATCH_SIZE = 1_000
    CONTENT_TYPE = "application/jsonl+gzip"
    ACTIVE_STORAGE_CHECKSUM_DIGEST = %w[M D 5].join

    def initialize(record_type:, before:, after: nil, project: nil, event_types: nil,
                   batch_size: DEFAULT_BATCH_SIZE,
                   prefix: InstanceConfiguration.value("archive_storage.prefix"),
                   storage_service: nil, dry_run: false, scope: nil, archive: nil,
                   selection: nil, protect_incomplete_deliveries: nil,
                   object_limit: nil, write_fence: nil, project_retention_run: nil)
      @record_type = record_type.to_s
      @before = before
      @after = after
      @project = project || archive&.project
      @event_types = Array(event_types).compact_blank.map(&:to_s)
      @batch_size = batch_size.to_i.positive? ? batch_size.to_i : DEFAULT_BATCH_SIZE
      @prefix = prefix.to_s.delete_prefix("/").delete_suffix("/")
      @archive = archive
      @storage_service = storage_service || archive_storage_service
      @storage_locator = archive&.lifecycle_metadata&.dig("storage_locator").presence ||
        InstanceConfiguration::ArchiveService.locator_for(@storage_service)
      @dry_run = dry_run
      @scope = (scope.presence || archive&.scope.presence || @record_type).to_s
      @selection = selection.presence || archive&.lifecycle_metadata&.dig("selection")
      @protect_incomplete_deliveries = if protect_incomplete_deliveries.nil?
        archive&.lifecycle_metadata&.dig("protect_incomplete_deliveries") == true
      else
        ActiveModel::Type::Boolean.new.cast(protect_incomplete_deliveries)
      end
      @object_limit = object_limit.to_i if object_limit.to_i.positive?
      @objects_processed = 0
      @write_fence = write_fence
      @project_retention_run = project_retention_run || archive&.project_retention_run
    end

    def call
      validate_configuration!
      return export_without_manifest if @dry_run || @project.blank?
      return manifest_result if @archive&.verified?
      return empty_result unless @archive || relation.exists?

      @archive ||= create_manifest!
      resume_manifest!
      manifest_result
    rescue SystemStackError => error
      fail_manifest!(error)
      raise Error.new(
        "Telemetry archive failed: #{error.class}: #{error.message}",
        archive: @archive
      )
    rescue Error => error
      fail_manifest!(error)
      raise Error.new(error.message, archive: error.archive || @archive)
    rescue StandardError => error
      fail_manifest!(error)
      raise Error.new(
        "Telemetry archive failed: #{error.class}: #{error.message}",
        archive: @archive
      )
    end

    private

    def validate_configuration!
      record_config
      raise Error, "Telemetry archive before boundary is required" if @before.blank?
    end

    def create_manifest!
      @sequence_upper_bound = relation.maximum(:id)
      @project.telemetry_archives.create!(
        project_retention_run: @project_retention_run,
        record_type: @record_type,
        scope: @scope,
        status: "pending",
        before_at: @before,
        after_at: @after,
        rows: 0,
        bytes: 0,
        expected_rows: 0,
        expected_bytes: 0,
        verified_rows: 0,
        verified_bytes: 0,
        dry_run: false,
        manifest_version: 2,
        exported_at: Time.current.utc,
        lifecycle_metadata: {
          "event_types" => @event_types,
          "batch_size" => @batch_size,
          "prefix" => @prefix,
          "selection" => @selection,
          "protect_incomplete_deliveries" => @protect_incomplete_deliveries,
          "sequence_upper_bound" => @sequence_upper_bound,
          "selection_created_at" => Time.current.utc.iso8601(6),
          "enumeration_complete" => false,
          "storage_locator" => @storage_locator
        }
      )
    end

    def resume_manifest!
      resumed = @archive.status == "failed"
      @archive.update!(
        status: (enumeration_complete? ? "verifying" : "uploading"),
        upload_started_at: @archive.upload_started_at || Time.current,
        failed_at: nil,
        error_message: nil,
        retry_count: @archive.retry_count.to_i + (resumed ? 1 : 0)
      )

      @archive.each_object_record do |object_record|
        next unless object_requires_upload?(object_record)
        break unless object_budget_available?

        records = records_for_references(object_record.normalized_source_references)
        upload_object_record!(object_record, records)
        consume_object_budget!
      end
      return if upload_work_remaining?

      enumerate_and_upload_remaining! unless enumeration_complete?
      return unless enumeration_complete?

      finalize_manifest_metadata!
      @archive.update!(
        status: "verifying",
        verification_started_at: @archive.verification_started_at || Time.current
      )
      return unless object_budget_available?

      verification = TelemetryArchiveInspector.new(
        archive: @archive,
        storage_service: @storage_service,
        persist: true,
        object_limit: remaining_object_budget,
        work_fence: @write_fence
      ).call
      @objects_processed += verification.fetch(:objects_processed)
    end

    def enumerate_and_upload_remaining!
      sequence = @archive.object_record_scope.maximum(:sequence).to_i
      sequence += 1 if @archive.object_record_scope.exists?
      remaining_relation.in_batches(of: @batch_size) do |batch_relation|
        break unless object_budget_available?

        records = batch_relation.order(:id).to_a
        next if records.empty?

        payload = gzip_records(records)
        object_record = build_object_record!(records, sequence, payload: payload)
        upload_object_record!(object_record, records, payload: payload)
        consume_object_budget!
        sequence += 1
      end

      update_lifecycle_metadata!("enumeration_complete" => true) unless remaining_relation.exists?
    end

    def build_object_record!(records, sequence, payload:)
      references = records.map { |record| source_reference(record) }

      TelemetryArchiveObject.create!(
        telemetry_archive: @archive,
        sequence: sequence,
        status: "pending",
        object_key: object_key(records, sequence),
        content_type: CONTENT_TYPE,
        checksum_sha256: Digest::SHA256.hexdigest(payload),
        checksum_md5_base64: active_storage_checksum(payload),
        expected_rows: records.size,
        expected_bytes: payload.bytesize,
        source_min_id: references.first.fetch("id"),
        source_max_id: references.last.fetch("id"),
        source_references: references,
        storage_generation: @storage_locator["generation_id"],
        storage_locator: @storage_locator
      )
    end

    def upload_object_record!(object_record, records, payload: nil)
      payload ||= gzip_records(records)
      validate_rebuilt_payload!(object_record, payload)
      object_record.update!(
        status: "uploading",
        attempts: object_record.attempts.to_i + 1,
        error_message: nil
      )

      with_project_external_write_fence do
        @storage_service.upload(
          object_record.object_key,
          StringIO.new(payload),
          checksum: object_record.checksum_md5_base64,
          content_type: object_record.content_type
        )
        object_record.update!(
          status: "uploaded",
          uploaded_at: Time.current,
          object_version_id: InstanceConfiguration::ArchiveService.object_version_id(
            @storage_service,
            object_record.object_key
          )
        )
      end
    rescue StandardError => error
      object_record&.update_columns(
        status: "failed",
        error_message: "#{error.class}: #{error.message}",
        updated_at: Time.current
      )
      raise Error.new(
        "Telemetry archive upload failed for #{object_record&.object_key}: #{error.class}: #{error.message}",
        archive: @archive
      )
    end

    def validate_rebuilt_payload!(object_record, payload)
      actual_checksum = Digest::SHA256.hexdigest(payload)
      return if actual_checksum == object_record.checksum_sha256 && payload.bytesize == object_record.expected_bytes

      raise Error.new(
        "Source rows changed after manifest object #{object_record.id} was recorded; create a new manifest",
        archive: @archive
      )
    end

    def finalize_manifest_metadata!
      refresh_expected_totals!
      @archive.reload
      checksum = @archive.manifest_checksum_sha256
      object_count = @archive.object_record_scope.count
      metadata = @archive.lifecycle_metadata.is_a?(Hash) ? @archive.lifecycle_metadata.dup : {}
      @archive.update!(
        checksum_sha256: checksum,
        uploaded_at: Time.current,
        rows: @archive.expected_rows,
        bytes: @archive.expected_bytes,
        objects: [],
        lifecycle_metadata: metadata.merge(
          "object_catalog" => "telemetry_archive_objects",
          "object_count" => object_count
        )
      )
    end

    def refresh_expected_totals!
      records = @archive.object_record_scope
      @archive.update!(
        expected_rows: records.sum(:expected_rows),
        expected_bytes: records.sum(:expected_bytes),
        source_min_id: records.minimum(:source_min_id),
        source_max_id: records.maximum(:source_max_id)
      )
    end

    def update_lifecycle_metadata!(updates)
      @archive.with_lock do
        metadata = @archive.lifecycle_metadata.is_a?(Hash) ? @archive.lifecycle_metadata.dup : {}
        @archive.update!(lifecycle_metadata: metadata.merge(updates.stringify_keys))
      end
    end

    def enumeration_complete?
      @archive.lifecycle_metadata.is_a?(Hash) && @archive.lifecycle_metadata["enumeration_complete"] == true
    end

    def object_requires_upload?(object_record)
      return false if object_record.status.in?(%w[uploaded verified])
      return false if object_record.status == "verifying" && object_record.uploaded_at.present?

      true
    end

    def upload_work_remaining?
      @archive.each_object_record.any? { |object_record| object_requires_upload?(object_record) }
    end

    def object_budget_available?
      @object_limit.nil? || @objects_processed < @object_limit
    end

    def remaining_object_budget
      return unless @object_limit

      [ @object_limit - @objects_processed, 0 ].max
    end

    def consume_object_budget!
      @objects_processed += 1
    end

    def relation
      column = model.arel_table[timestamp_column]
      result = model.where(column.lt(@before))
      result = result.where(column.gteq(@after)) if @after
      result = result.where(project_id: @project.id) if @project
      result = result.where(event_type: normalized_event_types) if @record_type == "ingest_events" && @event_types.any?
      result = apply_selection(result)
      if @protect_incomplete_deliveries
        result = TelemetryRetentionProtection.without_incomplete_deliveries(result)
      end
      upper_bound = sequence_upper_bound
      result = result.where("#{model.table_name}.id <= ?", upper_bound) if upper_bound
      result
    end

    def sequence_upper_bound
      @archive&.lifecycle_metadata&.dig("sequence_upper_bound") || @sequence_upper_bound
    end

    def apply_selection(result)
      return result if @selection.blank?
      unless @selection == "closed_error_groups" && @record_type == "ingest_events" && @project
        raise Error, "Unsupported telemetry archive selection: #{@selection.inspect}"
      end

      closed_group_ids = @project.error_groups
                                 .where.not(status: ErrorGroup.statuses.fetch("unresolved"))
                                 .where("last_seen_at < ?", @before)
                                 .select(:id)
      result.where(error_group_id: closed_group_ids)
    end

    def remaining_relation
      last_id = @archive.object_record_scope.maximum(:source_max_id)
      last_id ? relation.where("#{model.table_name}.id > ?", last_id) : relation
    end

    def records_for_references(references)
      records = if @record_type == "ingest_events"
        IngestEvent.for_partition_references(
          references,
          id_key: "id",
          occurred_at_key: "timestamp"
        ).where(project_id: @project.id).order(:id).to_a
      else
        TraceSpan.where(project_id: @project.id, id: references.pluck("id")).order(:id).to_a
      end

      expected_ids = references.pluck("id").map(&:to_i).sort
      actual_ids = records.map(&:id).sort
      return records if expected_ids == actual_ids

      raise Error.new(
        "Manifest source rows are missing (expected #{expected_ids.inspect}, found #{actual_ids.inspect})",
        archive: @archive
      )
    end

    def model
      record_config.fetch(:model)
    end

    def timestamp_column
      record_config.fetch(:timestamp_column)
    end

    def record_config
      RECORD_TYPES.fetch(@record_type) do
        raise Error, "Unsupported telemetry archive record type: #{@record_type.inspect}"
      end
    end

    def normalized_event_types
      @event_types.map { |event_type| IngestEvent.event_types.fetch(event_type) }
    rescue KeyError
      raise Error, "Unsupported ingest event type for archive: #{@event_types.inspect}"
    end

    def archive_storage_service
      locator = @archive&.lifecycle_metadata&.dig("storage_locator")
      InstanceConfiguration::ArchiveService.build(locator: locator)
    end

    def with_project_external_write_fence
      return yield unless @project

      Project.transaction(requires_new: true) do
        project = Project.lock.find_by(id: @project.id)
        if project.nil? || project.purge_pending?
          raise Error.new("Project purge is pending; refusing to create an archive object", archive: @archive)
        end

        @write_fence&.call
        yield
      end
    end

    def active_storage_checksum(payload)
      Digest.const_get(ACTIVE_STORAGE_CHECKSUM_DIGEST).base64digest(payload)
    end

    def gzip_records(records)
      io = StringIO.new
      derived_by_event_uuid = derived_evidence_index(records)
      Zlib::GzipWriter.wrap(io) do |gzip|
        gzip.mtime = exported_at.to_i
        records.each do |record|
          gzip.write(JSON.generate(archive_row(record, derived_evidence: derived_by_event_uuid[record.try(:uuid)])))
          gzip.write("\n")
        end
      end
      io.string
    end

    def archive_row(record, derived_evidence: nil)
      {
        archive_version: @archive ? 2 : 1,
        manifest_id: @archive&.id,
        record_type: @record_type,
        exported_at: exported_at.iso8601(6),
        source_identity: source_reference(record),
        restore_references: restore_references(record),
        export_policy: export_policy(record),
        derived_evidence: derived_evidence.presence,
        attributes: archive_attributes(record)
      }.compact
    end

    def archive_attributes(record)
      Logister::TelemetryRedactor.call(record.attributes.as_json)
    end

    def derived_evidence_index(records)
      return {} unless @record_type == "ingest_events" && @project

      uuids = records.filter_map { |record| record.try(:uuid) }
      @project.mobile_event_enrichments.where(event_uuid: uuids).group_by(&:event_uuid).transform_values do |enrichments|
        enrichments.map do |enrichment|
          Logister::TelemetryRedactor.call(
            {
              "uuid" => enrichment.uuid,
              "event_occurred_at" => enrichment.event_occurred_at&.utc&.iso8601(6),
              "platform" => enrichment.platform,
              "kind" => enrichment.kind,
              "status" => enrichment.status,
              "input_sha256" => enrichment.input_sha256,
              "artifact_type" => enrichment.artifact_type,
              "artifact_uuid" => enrichment.artifact_uuid,
              "artifact_checksum_sha256" => enrichment.artifact_checksum_sha256,
              "tool_name" => enrichment.tool_name,
              "tool_version" => enrichment.tool_version,
              "data" => enrichment.data,
              "processed_at" => enrichment.processed_at&.utc&.iso8601(6)
            }.compact
          )
        end
      end
    end

    def export_policy(record)
      policy = {
        "payload" => "server_redacted",
        "redaction" => "sensitive_key_v1",
        "original_evidence_included" => false
      }
      return policy unless record.is_a?(IngestEvent)

      evidence = TelemetryEvidence.for(record)
      policy.merge(
        "evidence" => {
          "source" => evidence.source,
          "evidence_kind" => evidence.evidence_kind,
          "identity_scope" => evidence.identity_scope,
          "time_precision" => evidence.time_precision,
          "occurred_at" => evidence.occurred_at&.utc&.iso8601(6),
          "reporting_start" => evidence.reporting_start&.utc&.iso8601(6),
          "reporting_end" => evidence.reporting_end&.utc&.iso8601(6),
          "received_at" => evidence.received_at&.utc&.iso8601(6)
        }.compact,
        "producer" => Logister::TelemetryRedactor.call(evidence.producer.as_json),
        "normalization" => Logister::TelemetryRedactor.call(evidence.normalization.as_json)
      )
    end

    def source_reference(record)
      {
        "id" => record.id,
        "timestamp" => record.public_send(timestamp_column)&.utc&.iso8601(6)
      }
    end

    def restore_references(record)
      return unless record.is_a?(IngestEvent)

      { "api_key_id" => record.api_key_id }
    end

    def exported_at
      @archive&.exported_at || @exported_at ||= Time.current.utc
    end

    def object_key(records, sequence = nil)
      if @archive
        return [
          @prefix.presence,
          "manifests",
          "project=#{@project.uuid}",
          "archive=#{@archive.id}",
          @record_type,
          format("part-%06d-%s-%s.jsonl.gz", sequence, records.first.id, records.last.id)
        ].compact.join("/")
      end

      timestamp = records.first.public_send(timestamp_column).utc
      range = "#{records.first.id}-#{records.last.id}"
      [
        @prefix.presence,
        @record_type,
        @project ? "project=#{@project.uuid}" : nil,
        "year=#{timestamp.year}",
        "month=#{timestamp.strftime('%m')}",
        "day=#{timestamp.strftime('%d')}",
        "#{exported_at.strftime('%Y%m%dT%H%M%SZ')}-#{range}.jsonl.gz"
      ].compact.join("/")
    end

    def export_without_manifest
      exported_rows = 0
      objects = []

      relation.in_batches(of: @batch_size) do |batch_relation|
        records = batch_relation.order(:id).to_a
        next if records.empty?

        payload = gzip_records(records)
        key = object_key(records)
        checksum = active_storage_checksum(payload)
        exported_rows += records.size

        unless @dry_run
          @storage_service.upload(key, StringIO.new(payload), checksum: checksum, content_type: CONTENT_TYPE)
        end

        objects << {
          key: key,
          rows: records.size,
          bytes: payload.bytesize,
          checksum_sha256: Digest::SHA256.hexdigest(payload),
          dry_run: @dry_run
        }
      end

      {
        record_type: @record_type,
        project_id: @project&.id,
        before: @before.utc.iso8601,
        after: @after&.utc&.iso8601,
        batch_size: @batch_size,
        objects: objects,
        rows: exported_rows,
        dry_run: @dry_run
      }
    rescue StandardError => error
      raise error if error.is_a?(Error)

      raise Error, "Telemetry archive upload failed: #{error.class}: #{error.message}"
    end

    def manifest_result
      return empty_result unless @archive

      @archive.reload
      objects = @archive.object_summaries
      object_count = @archive.object_record_scope.count
      {
        archive_id: @archive.id,
        record_type: @archive.record_type,
        project_id: @archive.project_id,
        before: @archive.before_at.utc.iso8601,
        after: @archive.after_at&.utc&.iso8601,
        batch_size: @archive.lifecycle_metadata["batch_size"] || @batch_size,
        objects: objects,
        object_count: object_count,
        objects_truncated: object_count > objects.size,
        rows: @archive.expected_rows,
        bytes: @archive.expected_bytes,
        checksum_sha256: @archive.checksum_sha256,
        source_reference_count: @archive.expected_rows,
        verified: @archive.verified?,
        continuation_required: !@archive.verified?,
        objects_processed_this_attempt: @objects_processed,
        dry_run: false
      }
    end

    def empty_result
      {
        record_type: @record_type,
        project_id: @project&.id,
        before: @before.utc.iso8601,
        after: @after&.utc&.iso8601,
        batch_size: @batch_size,
        objects: [],
        rows: 0,
        bytes: 0,
        source_reference_count: 0,
        verified: false,
        continuation_required: false,
        dry_run: @dry_run
      }
    end

    def fail_manifest!(error)
      return unless @archive&.persisted?

      @archive.update_columns(
        status: "failed",
        failed_at: Time.current,
        error_message: "#{error.class}: #{error.message}",
        updated_at: Time.current
      )
    rescue StandardError => persistence_error
      Rails.logger.error(
        "telemetry_archive.failure_record_error archive_id=#{@archive.id} " \
        "error=#{persistence_error.class}: #{persistence_error.message}"
      )
    end
  end
end

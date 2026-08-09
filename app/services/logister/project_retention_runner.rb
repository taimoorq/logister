module Logister
  class ProjectRetentionRunner
    class SourceRetirementError < StandardError; end

    DEFAULT_BATCH_SIZE = 1_000
    HOT_EVENT_TYPES = IngestEvent.event_types.keys.excluding("error").freeze

    def initialize(project:, policy: nil, batch_size: DEFAULT_BATCH_SIZE, storage_service: nil, dry_run: false, now: Time.current)
      @project = project
      @batch_size = batch_size.to_i.positive? ? batch_size.to_i : DEFAULT_BATCH_SIZE
      @storage_service = storage_service
      @dry_run = dry_run
      @policy = policy || default_policy
      @now = now
    end

    def call
      @current_archives = {}
      result = {
        project_id: @project.id,
        project_uuid: @project.uuid,
        dry_run: @dry_run,
        archive_enabled: @policy.archive_enabled?,
        archive_before_delete: @policy.archive_before_delete?,
        cutoffs: cutoffs.transform_values { |value| value&.utc&.iso8601 },
        archives: [],
        recovered_deletions: cleanup_verified_archive_sources,
        candidates: {},
        protected_by_delivery: {},
        deleted: {}
      }

      result[:candidates][:hot_events] = hot_event_scope.count
      result[:candidates][:trace_spans] = trace_span_scope.count
      result[:candidates][:closed_error_groups] = closed_error_group_scope.count
      result[:protected_by_delivery][:hot_events] = protected_source_count(hot_event_scope)
      result[:protected_by_delivery][:trace_spans] = protected_source_count(trace_span_scope)
      result[:protected_by_delivery][:error_events] = protected_source_count(closed_error_event_scope)

      archive_retention_scope(result, :hot_events, "ingest_events", hot_cutoff, event_types: HOT_EVENT_TYPES)
      archive_retention_scope(result, :trace_spans, "trace_spans", trace_cutoff)
      archive_retention_scope(result, :error_events, "ingest_events", error_cutoff, event_types: [ "error" ]) if error_cutoff

      if archive_deletion_guard?
        result[:deleted][:hot_events] = delete_current_archive_sources(:hot_events)
        result[:deleted][:trace_spans] = delete_current_archive_sources(:trace_spans)
        result[:deleted][:error_events] = delete_current_archive_sources(:error_events)
      else
        result[:deleted][:hot_events] = delete_events(hot_event_scope)
        result[:deleted][:trace_spans] = delete_trace_spans(trace_span_scope)
      end
      result[:deleted][:closed_error_groups] = prune_closed_error_groups

      mark_policy_run!(result)
      result
    end

    private

    def default_policy
      return @project.retention_policy || @project.build_retention_policy if @dry_run

      ProjectRetentionPolicy.for(project: @project)
    end

    def cutoffs
      {
        hot_events: hot_cutoff,
        trace_spans: trace_cutoff,
        error_events: error_cutoff
      }
    end

    def hot_cutoff
      @hot_cutoff ||= @now - @policy.hot_retention_days.days
    end

    def trace_cutoff
      @trace_cutoff ||= @now - @policy.trace_retention_days.days
    end

    def error_cutoff
      return nil if @policy.error_retention_days.blank?

      @error_cutoff ||= @now - @policy.error_retention_days.days
    end

    def hot_event_scope
      @project.ingest_events
              .where("occurred_at < ?", hot_cutoff)
              .where(event_type: HOT_EVENT_TYPES.map { |event_type| IngestEvent.event_types.fetch(event_type) })
              .where(error_group_id: nil)
    end

    def trace_span_scope
      @project.trace_spans.where("started_at < ?", trace_cutoff)
    end

    def closed_error_group_scope
      return ErrorGroup.none unless error_cutoff

      @project.error_groups
              .where.not(status: ErrorGroup.statuses.fetch("unresolved"))
              .where("last_seen_at < ?", error_cutoff)
    end

    def closed_error_event_scope
      return IngestEvent.none unless error_cutoff

      @project.ingest_events.where(error_group_id: closed_error_group_scope.select(:id))
    end

    def protected_source_count(scope)
      TelemetryRetentionProtection.with_incomplete_deliveries(scope).count
    end

    def archive_retention_scope(result, scope, record_type, before, event_types: nil)
      return unless archive_deletion_guard?
      return unless before

      retry_archive = retryable_archive_for(scope)
      archive_result = if retry_archive && !@dry_run
        TelemetryArchiveRetry.new(archive: retry_archive, storage_service: @storage_service).call
      else
        TelemetryArchiveExporter.new(
          record_type: record_type,
          project: @project,
          scope: scope,
          before: before,
          after: nil,
          event_types: event_types,
          selection: ("closed_error_groups" if scope == :error_events),
          protect_incomplete_deliveries: true,
          batch_size: @batch_size,
          storage_service: @storage_service,
          dry_run: @dry_run
        ).call
      end

      archive_summary = archive_result.merge(scope: scope)
      result[:archives] << archive_summary
      if !@dry_run && archive_result.fetch(:rows).positive?
        unless archive_result.fetch(:verified)
          raise TelemetryArchiveExporter::Error, "Archive manifest was not verified"
        end

        @current_archives[scope.to_sym] = @project.telemetry_archives.find(archive_result.fetch(:archive_id))
        @policy.update!(last_archive_run_at: @now)
      end
    rescue TelemetryArchiveExporter::Error => e
      record_archive_failure!(scope, record_type, before, nil, e) unless @dry_run || e.archive
      notify_archive_failure(scope, record_type, before, nil, e) unless @dry_run
      raise
    end

    def archive_deletion_guard?
      @policy.archive_enabled? && @policy.archive_before_delete?
    end

    def retryable_archive_for(scope)
      @project.telemetry_archives
              .resumable
              .where(scope: scope.to_s, source_deleted_at: nil)
              .where("manifest_version >= 2")
              .recent_first
              .first
    end

    def cleanup_verified_archive_sources
      return {} if @dry_run || !archive_deletion_guard?

      @project.telemetry_archives
              .verified
              .where(source_deleted_at: nil, scope: %w[hot_events trace_spans error_events])
              .where("manifest_version >= 2")
              .each_with_object(Hash.new(0)) do |archive, totals|
        totals[archive.scope.to_sym] += delete_archive_sources!(archive)
      end
    end

    def delete_current_archive_sources(scope)
      archive = @current_archives[scope.to_sym]
      return 0 unless archive

      delete_archive_sources!(archive)
    end

    def delete_archive_sources!(archive)
      ensure_archive_storage_generation!(archive)
      verification = TelemetryArchiveInspector.new(
        archive: archive,
        storage_service: @storage_service,
        persist: false
      ).call
      deleted = 0
      remaining = 0
      deletable_remaining = 0
      protected_delivery_rows = 0
      protected_reopened_group_rows = 0

      archive.object_records.reorder(:id).find_each(batch_size: 1) do |object_record|
        references = object_record.normalized_source_references
        deleted += delete_archive_object_sources!(archive, references)
        remaining += count_archive_sources(archive, references)
        deletable_remaining += count_archive_sources(archive, references) do |relation|
          archive_deletion_eligible_relation(archive, relation)
        end
        protected_delivery_rows += count_archive_sources(archive, references) do |relation|
          TelemetryRetentionProtection.with_incomplete_deliveries(relation)
        end
        if error_event_archive?(archive)
          protected_reopened_group_rows += count_archive_sources(archive, references) do |relation|
            outside_closed_error_groups(relation)
          end
        end
      end
      if deletable_remaining.positive?
        raise TelemetryArchiveExporter::Error.new(
          "Verified archive #{archive.id} still has #{deletable_remaining} eligible source rows after deletion",
          archive: archive
        )
      end

      cleanup_complete = remaining.zero?
      archive.update!(
        source_deleted_at: (cleanup_complete ? @now : nil),
        source_deleted_rows: [ archive.expected_rows - remaining, 0 ].max,
        lifecycle_metadata: (archive.lifecycle_metadata || {}).merge(
          "source_cleanup" => {
            "attempted_at" => @now.utc.iso8601,
            "completed_at" => (@now.utc.iso8601 if cleanup_complete),
            "deleted_rows_this_attempt" => deleted,
            "deleted_rows_total" => [ archive.expected_rows - remaining, 0 ].max,
            "verified_remaining_rows" => remaining,
            "protected_delivery_rows" => protected_delivery_rows,
            "protected_reopened_group_rows" => protected_reopened_group_rows,
            "manifest_reverified_at" => @now.utc.iso8601,
            "manifest_reverified_rows" => verification.fetch(:rows),
            "policy_cutoff" => cutoff_for_archive(archive)&.utc&.iso8601
          }
        )
      )
      deleted
    end

    def ensure_archive_storage_generation!(archive)
      return if @storage_service
      return if archive.lifecycle_metadata&.dig("storage_locator").present?
      return if ActiveModel::Type::Boolean.new.cast(
        ENV.fetch("LOGISTER_ATTEST_LEGACY_ARCHIVE_STORAGE_CURRENT", "false")
      )

      raise TelemetryArchiveExporter::Error.new(
        "Verified archive #{archive.id} predates immutable storage locators; refusing source cleanup without an explicit current-store attestation",
        archive: archive
      )
    end

    def delete_archive_object_sources!(archive, references)
      if error_event_archive?(archive)
        delete_closed_error_archive_sources(references)
      elsif archive.record_type == "ingest_events"
        eligible = eligible_archive_references(archive, references)
        delete_events_by_references(eligible.map { |reference| [ reference["id"], reference["timestamp"] ] })
      else
        delete_trace_spans_by_references(eligible_archive_references(archive, references))
      end
    end

    # Error-group status is revalidated after the archive read-back and before
    # source deletion. Locking the workflow rows serializes this decision with
    # ErrorGroup#record_occurrence!, which takes the same row lock when a new
    # occurrence reopens a resolved/ignored/archived group.
    def delete_closed_error_archive_sources(references)
      group_ids = ingest_event_group_ids_for_references(references)
      return 0 if group_ids.empty?

      ErrorGroup.transaction do
        ErrorGroup.where(project_id: @project.id, id: group_ids).order(:id).lock.load
        eligible_group_ids = closed_error_group_scope.where(id: group_ids).pluck(:id)
        eligible_references = ingest_event_references_for_groups(references, eligible_group_ids)
        delete_events_by_references(eligible_references)
      end
    end

    def ingest_event_group_ids_for_references(references)
      partition_references(references).each_slice(IngestEvent::PARTITION_REFERENCE_BATCH_SIZE).flat_map do |batch|
        IngestEvent.for_partition_references(batch, id_key: :id, occurred_at_key: :occurred_at)
                   .where(project_id: @project.id)
                   .where.not(error_group_id: nil)
                   .distinct
                   .pluck(:error_group_id)
      end.uniq
    end

    def ingest_event_references_for_groups(references, group_ids)
      return [] if group_ids.empty? || error_cutoff.blank?

      partition_references(references).each_slice(IngestEvent::PARTITION_REFERENCE_BATCH_SIZE).flat_map do |batch|
        IngestEvent.for_partition_references(batch, id_key: :id, occurred_at_key: :occurred_at)
                   .where(project_id: @project.id, error_group_id: group_ids)
                   .where("occurred_at < ?", error_cutoff)
                   .pluck(:id, :occurred_at)
      end
    end

    def partition_references(references)
      references.map do |reference|
        { id: reference["id"], occurred_at: reference["timestamp"] }
      end
    end

    def error_event_archive?(archive)
      archive.record_type == "ingest_events" && archive.scope == "error_events"
    end

    def archive_source_relations(archive, references)
      if archive.record_type == "ingest_events"
        partition_references(references).each_slice(IngestEvent::PARTITION_REFERENCE_BATCH_SIZE).map do |batch|
          IngestEvent.for_partition_references(batch, id_key: :id, occurred_at_key: :occurred_at)
                     .where(project_id: @project.id)
        end
      else
        [ TraceSpan.where(project_id: @project.id, id: references.pluck("id")) ]
      end
    end

    def count_archive_sources(archive, references)
      archive_source_relations(archive, references).sum do |relation|
        scoped_relation = block_given? ? yield(relation) : relation
        scoped_relation.count
      end
    end

    def archive_deletion_eligible_relation(archive, relation)
      relation = TelemetryRetentionProtection.without_incomplete_deliveries(relation)
      case archive.scope
      when "hot_events"
        relation.where("ingest_events.occurred_at < ?", hot_cutoff)
                .where(event_type: HOT_EVENT_TYPES.map { |event_type| IngestEvent.event_types.fetch(event_type) })
                .where(error_group_id: nil)
      when "trace_spans"
        relation.where("trace_spans.started_at < ?", trace_cutoff)
      when "error_events"
        return relation.none if error_cutoff.blank?

        relation.where("ingest_events.occurred_at < ?", error_cutoff)
                .where(error_group_id: closed_error_group_scope.select(:id))
      else
        relation.none
      end
    end

    def eligible_archive_references(archive, references)
      archive_source_relations(archive, references).flat_map do |relation|
        eligible = archive_deletion_eligible_relation(archive, relation)
        timestamp_column = archive.record_type == "ingest_events" ? :occurred_at : :started_at
        eligible.pluck(:id, timestamp_column).map do |id, timestamp|
          { "id" => id, "timestamp" => timestamp }
        end
      end
    end

    def cutoff_for_archive(archive)
      case archive.scope
      when "hot_events" then hot_cutoff
      when "trace_spans" then trace_cutoff
      when "error_events" then error_cutoff
      end
    end

    def outside_closed_error_groups(relation)
      closed_ids = closed_error_group_scope.select(:id)
      relation.where(error_group_id: nil).or(relation.where.not(error_group_id: closed_ids))
    end

    def delete_trace_spans_by_references(references)
      span_references = references.filter_map do |reference|
        id = reference["id"] || reference[:id]
        started_at = reference["timestamp"] || reference[:timestamp] || reference[:started_at]
        { id: id, started_at: started_at } if id.present? && started_at.present?
      end.uniq
      return 0 if span_references.empty?

      span_references.each_slice(@batch_size).sum do |reference_batch|
        with_locked_delivery_state(
          "TraceSpan",
          reference_batch,
          recorded_at_key: :started_at
        ) do |keys|
          relation = TraceSpan.where(project_id: @project.id, id: reference_batch.pluck(:id))
          deletable_references = TelemetryRetentionProtection.without_incomplete_deliveries(relation)
                                                               .order(:id)
                                                               .lock
                                                               .pluck(:id, :started_at)
                                                               .map { |id, started_at| { id: id, started_at: started_at } }
          deleted = TelemetryRetentionProtection.without_incomplete_deliveries(relation).delete_all
          ensure_exact_source_deletion!("TraceSpan", deletable_references.length, deleted)
          retire_source_keys!(keys, deletable_references, recorded_at_key: :started_at)
          deleted
        end
      end
    end

    def record_archive_failure!(scope, record_type, before, after, error)
      @project.telemetry_archives.create!(
        scope: scope.to_s,
        record_type: record_type,
        status: "failed",
        before_at: before,
        after_at: after,
        rows: 0,
        bytes: 0,
        objects: [],
        dry_run: false,
        error_message: "#{error.class}: #{error.message}"
      )
    end

    def notify_archive_failure(scope, record_type, before, after, error)
      ProjectRetentionNotificationJob.perform_later(
        @project.id,
        {
          "scope" => scope.to_s,
          "record_type" => record_type,
          "before_at" => before&.utc&.iso8601,
          "after_at" => after&.utc&.iso8601,
          "error_class" => error.class.name,
          "error_message" => error.message
        }
      )
    end

    def delete_events(scope)
      return 0 if @dry_run

      deleted = 0
      TelemetryRetentionProtection.without_incomplete_deliveries(scope).in_batches(of: @batch_size) do |batch|
        deleted += delete_events_by_references(batch.pluck(:id, :occurred_at))
      end
      deleted
    end

    def delete_trace_spans(scope)
      return 0 if @dry_run

      deleted = 0
      TelemetryRetentionProtection.without_incomplete_deliveries(scope).in_batches(of: @batch_size) do |batch|
        references = batch.pluck(:id, :started_at).map do |id, started_at|
          { "id" => id, "timestamp" => started_at }
        end
        deleted += delete_trace_spans_by_references(references)
      end
      deleted
    end

    def prune_closed_error_groups
      scope = closed_error_group_scope
      return 0 if @dry_run

      deleted = 0
      scope.find_each(batch_size: @batch_size) do |group|
        removed = group.with_lock do
          group.reload
          next false unless closed_error_group?(group)

          event_references = (
            group.error_occurrences.pluck(:ingest_event_id, :ingest_event_occurred_at) +
            IngestEvent.where(error_group_id: group.id).pluck(:id, :occurred_at)
          ).uniq
          delete_events_by_references(event_references)
          next false if group.error_occurrences.exists? || IngestEvent.where(error_group_id: group.id).exists?

          group.destroy!
          true
        end
        deleted += 1 if removed
      end
      deleted
    end

    def closed_error_group?(group)
      error_cutoff && !group.unresolved? && group.last_seen_at < error_cutoff
    end

    def delete_events_by_references(references)
      event_references = Array(references).filter_map do |id, occurred_at|
        next if id.blank?

        { id: id, occurred_at: occurred_at }
      end.uniq
      event_ids = event_references.pluck(:id)
      return 0 if event_ids.empty?

      with_locked_delivery_state(
        "IngestEvent",
        event_references,
        recorded_at_key: :occurred_at
      ) do |keys|
        deletable_references = unprotected_event_references(event_references)
        deletable_ids = deletable_references.pluck(:id)
        next 0 if deletable_ids.empty?

        clear_event_references(deletable_ids)
        ErrorOccurrence.where(ingest_event_id: deletable_ids).delete_all
        deleted = delete_partitioned_events(deletable_references)
        ensure_exact_source_deletion!("IngestEvent", deletable_references.length, deleted)
        retire_source_keys!(keys, deletable_references, recorded_at_key: :occurred_at)
        deleted
      end
    end

    def unprotected_event_references(references)
      Array(references).each_slice(IngestEvent::PARTITION_REFERENCE_BATCH_SIZE).flat_map do |reference_batch|
        relation = IngestEvent.for_partition_references(
          reference_batch,
          id_key: :id,
          occurred_at_key: :occurred_at
        ).where(project_id: @project.id)
        TelemetryRetentionProtection.without_incomplete_deliveries(relation)
                                      .order(:id)
                                      .lock
                                      .pluck(:id, :occurred_at)
                                      .map { |id, occurred_at| { id: id, occurred_at: occurred_at } }
      end
    end

    def delete_partitioned_events(references)
      Array(references).each_slice(IngestEvent::PARTITION_REFERENCE_BATCH_SIZE).sum do |reference_batch|
        IngestEvent.for_partition_references(reference_batch, id_key: :id, occurred_at_key: :occurred_at)
                   .where(project_id: @project.id)
                   .then { |relation| TelemetryRetentionProtection.without_incomplete_deliveries(relation) }
                   .delete_all
      end
    end

    def with_locked_delivery_state(record_type, references, recorded_at_key:)
      TelemetryIdempotencyKey.transaction(requires_new: true) do
        keys = TelemetryIdempotencyKey.for_source_references(
          project_id: @project.id,
          record_type: record_type,
          references: references,
          id_key: :id,
          recorded_at_key: recorded_at_key
        ).order(:id).lock.to_a
        outbox_ids = TelemetryOutboxEvent.where(telemetry_idempotency_key_id: keys.map(&:id))
                                          .order(:id)
                                          .lock
                                          .pluck(:id)
        TelemetryDelivery.where(telemetry_outbox_event_id: outbox_ids).order(:id).lock.load if outbox_ids.any?
        yield(keys)
      end
    end

    def retire_source_keys!(keys, references, recorded_at_key:)
      identities = references.map do |reference|
        [ reference.fetch(:id).to_i, reference.fetch(recorded_at_key).to_time.to_f ]
      end.to_set
      retired_keys = keys.select do |key|
        identities.include?([ key.record_id.to_i, key.recorded_at.to_time.to_f ])
      end
      return if retired_keys.empty?

      retired_at = Time.current
      TelemetryIdempotencyKey.where(id: retired_keys.map(&:id), source_retired_at: nil)
                             .update_all(source_retired_at: retired_at, updated_at: retired_at)
      retired_keys.each { |key| key.source_retired_at ||= retired_at }
    end

    def ensure_exact_source_deletion!(record_type, expected, deleted)
      return if expected == deleted

      raise SourceRetirementError,
            "#{record_type} retention deleted #{deleted} of #{expected} locked eligible sources"
    end

    def clear_event_references(ids)
      event_ids = Array(ids).compact
      return if event_ids.empty?

      CheckInMonitor.where(last_event_id: event_ids).update_all(last_event_id: nil, last_event_occurred_at: nil, updated_at: @now)
      ErrorGroup.where(latest_event_id: event_ids).update_all(latest_event_id: nil, latest_event_occurred_at: nil, updated_at: @now)
    end

    def mark_policy_run!(result)
      return if @dry_run

      @policy.update!(
        last_retention_run_at: @now,
        last_retention_result: result.as_json
      )
    end
  end
end

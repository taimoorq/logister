# frozen_string_literal: true

require "digest"

module Logister
  class TelemetryProjector
    Result = Data.define(:claimed, :completed, :retried, :terminal_failed) do
      def work?
        claimed.positive?
      end
    end

    class ProjectionError < StandardError; end
    class MissingSourceRecord < ProjectionError; end
    class PayloadTooLarge < ProjectionError; end
    class ProjectPurging < ProjectionError; end
    class ClickhouseDisabled < ProjectionError; end
    class InvalidProjection < ProjectionError; end

    MAX_BATCH_ROWS = 200
    MAX_BATCH_BYTES = 1.megabyte

    def initialize(clickhouse_client: ClickhouseClient.new, now: -> { Time.current }, metrics: TelemetryPipelineMetrics.new(operation: "projection", sampled: false))
      @clickhouse_client = clickhouse_client
      @now = now
      @metrics = metrics
      reset_counts
    end

    def call(limit: MAX_BATCH_ROWS, run: nil)
      reset_counts
      @run = run
      @started_delivery_ids = Set.new
      return result unless continue_work?

      options = { limit: limit, now: now }
      options[:synchronous_limit] = TelemetryProjectionRun::SYNCHRONOUS_CLAIM_LIMIT if run
      deliveries = @metrics.measure(:claim) { TelemetryDelivery.claim_batch(**options) }
      @claimed = deliveries.length
      return result if deliveries.empty?

      if deliveries.first.destination.in?(TelemetryDelivery::CLICKHOUSE_DESTINATIONS)
        project_clickhouse(deliveries)
      else
        deliveries.each do |delivery|
          break unless continue_work?

          project_single(delivery)
        end
      end
      result
    ensure
      if run && deliveries.present?
        unstarted = deliveries.reject { |delivery| @started_delivery_ids.include?(delivery.id) }
        released = TelemetryDelivery.release_unstarted_batch!(unstarted, at: now) if unstarted.any?
        @metrics.count(:yielded, released.to_i)
      end
      @run = nil
    end

    def project_synchronously!(outbox_event)
      reset_counts
      outbox_event.telemetry_deliveries
        .where(destination: TelemetryDelivery::SYNCHRONOUS_DESTINATIONS)
        .order(:id)
        .find_each do |delivery|
          next if delivery.completed? || delivery.terminal_failed?
          next unless delivery.claim!(now: now)

          @claimed += 1
          project_single(delivery)
        end
      result
    end

    private

    attr_reader :clickhouse_client

    def now
      @now.call
    end

    def reset_counts
      @claimed = 0
      @completed = 0
      @retried = 0
      @terminal_failed = 0
    end

    def result
      Result.new(@claimed, @completed, @retried, @terminal_failed)
    end

    def project_single(delivery)
      start_deliveries!([ delivery ])
      TelemetryDelivery.renew_batch_lease!([ delivery ], at: now) if @run
      ensure_project_active!(delivery)
      record = source_record!(delivery)

      case delivery.destination
      when "deployment_index"
        projection = ProjectDeploymentIndexer.from_event(record)
        if projection.errors.any?
          raise InvalidProjection, "Deployment projection rejected: #{projection.errors.join(', ')}"
        end
      when "error_grouping"
        ErrorGroupingService.call(record, notifications: send_notifications?(delivery))
      when "check_in_monitor"
        CheckInMonitor.record!(project: record.project, event: record)
      else
        raise ProjectionError, "Unsupported single delivery destination: #{delivery.destination}"
      end

      complete!(delivery)
    rescue StandardError => error
      fail!(delivery, error, terminal: poison_error?(error))
    end

    def project_clickhouse(deliveries)
      if deliveries.any? { |delivery| delivery.batch_key.present? }
        identity = deliveries.first.attributes.symbolize_keys.slice(:project_id, :destination, :batch_key)
        persisted_batch = TelemetryProjectionBatch.find_by(identity)
        # Disabling new batch creation must still drain bodies already committed
        # by this version. Only downgrade the image after those records drain.
        return retry_clickhouse_batch(deliveries, batch: persisted_batch) if persisted_batch || batched_projection?
      end

      preload_sources(deliveries) if batched_projection?
      pairs = deliveries.filter_map do |delivery|
        return unless continue_work?

        ensure_project_active!(delivery)
        record = source_record!(delivery)
        attributes = clickhouse_attributes(delivery, record)
        unless attributes
          complete!(delivery)
          next
        end

        encoded = attributes.to_json
        if encoded.bytesize > MAX_BATCH_BYTES
          fail!(delivery, PayloadTooLarge.new("ClickHouse row exceeds #{MAX_BATCH_BYTES} bytes"), terminal: true)
          next
        end
        { delivery: delivery, record: record, attributes: attributes, bytes: encoded.bytesize + 1 }
      rescue StandardError => error
        fail!(delivery, error, terminal: poison_error?(error))
        nil
      end

      byte_bounded_chunks(pairs).each do |chunk|
        break unless continue_work?

        insert_clickhouse_chunk(chunk)
      end
    ensure
      @projection_sources = nil
    end

    def clickhouse_attributes(delivery, record)
      case delivery.destination
      when "clickhouse_event"
        ingestor = EventIngestor.new(
          event: record,
          request_context: delivery.telemetry_outbox_event.request_context,
          clickhouse_client: clickhouse_client
        )
        return if ingestor.suppressed?
        raise ClickhouseDisabled, "ClickHouse writes are disabled" unless ingestor.projectable?

        ingestor.attributes
      when "clickhouse_span"
        ingestor = SpanIngestor.new(
          span: record,
          request_context: delivery.telemetry_outbox_event.request_context,
          clickhouse_client: clickhouse_client
        )
        raise ClickhouseDisabled, "ClickHouse writes are disabled" unless ingestor.projectable?

        ingestor.attributes
      else
        raise ProjectionError, "Unsupported ClickHouse destination: #{delivery.destination}"
      end
    end

    def byte_bounded_chunks(pairs)
      pairs.each_with_object([]) do |pair, chunks|
        chunk = chunks.last
        if chunk.nil? || chunk.length >= MAX_BATCH_ROWS || chunk.sum { |item| item.fetch(:bytes) } + pair.fetch(:bytes) > MAX_BATCH_BYTES
          chunks << [ pair ]
        else
          chunk << pair
        end
      end
    end

    def insert_clickhouse_chunk(chunk)
      return insert_new_projection_batch(chunk) if batched_projection?

      deliveries = chunk.map { |item| item.fetch(:delivery) }
      project_ids = deliveries.map(&:project_id).uniq
      raise ProjectionError, "A ClickHouse batch cannot span projects" unless project_ids.one?

      batch_key = stable_batch_key(deliveries)
      if @run
        TelemetryDelivery.assign_batch_key_batch!(deliveries, batch_key: batch_key)
      else
        deliveries.each { |delivery| delivery.assign_batch_key!(batch_key) }
      end
      deliveries.each { |delivery| ensure_project_active!(delivery) }
      rows = chunk.map { |item| item.fetch(:attributes) }

      # Shared writers block ProjectPurgeRequest's exclusive tombstone lock, but
      # permit other writers and the KEY SHARE locks taken by ingestion foreign
      # keys. Keep the fence across the external write: releasing it early could
      # recreate ClickHouse data after the purge mutation has been verified.
      Project.transaction(requires_new: true) do
        project = Project.lock("FOR SHARE").find_by(id: project_ids.first)
        raise ProjectPurging, "Project purge is pending" if project.nil? || project.purge_pending?
        next unless begin_external_write?(deliveries)

        @metrics.measure(:insert) do
          SelfReportingGuard.suppress do
            if deliveries.first.destination == "clickhouse_event"
              clickhouse_client.insert_events!(rows, deduplication_token: batch_key, gzip: true)
            else
              clickhouse_client.insert_spans!(rows, deduplication_token: batch_key, gzip: true)
            end
          end
        end
      end
      deliveries.each { |delivery| complete!(delivery) } if !@run || deliveries.all? { |delivery| @started_delivery_ids.include?(delivery.id) }
    rescue StandardError => error
      fail_batch!(deliveries, error)
      report_clickhouse_failure(chunk&.first, error)
    end

    def batched_projection?
      ENV["LOGISTER_BATCHED_PROJECTION"] == "true"
    end

    def preload_sources(deliveries)
      @projection_sources = @metrics.measure(:source_load) { TelemetryProjectionSources.new(deliveries) }
    end

    def insert_new_projection_batch(chunk)
      deliveries = chunk.map { |item| item.fetch(:delivery) }
      payload = "#{chunk.map { |item| item.fetch(:attributes).to_json }.join("\n")}\n"
      batch = @metrics.measure(:batch_persistence) do
        TelemetryProjectionBatch.prepare!(deliveries: deliveries, batch_key: stable_batch_key(deliveries), payload: payload)
      end
      @metrics.count(:persisted_payload_bytes, payload.bytesize)
      send_projection_batch(batch, deliveries)
    rescue StandardError => error
      fail_batch!(deliveries, error)
      report_clickhouse_failure(chunk&.first, error)
    end

    def retry_clickhouse_batch(deliveries, batch: nil)
      identity = deliveries.first.attributes.symbolize_keys.slice(:project_id, :destination, :batch_key)
      unless deliveries.all? { |delivery| delivery.attributes.symbolize_keys.slice(*identity.keys) == identity }
        raise TelemetryProjectionBatch::InvalidPayload, "Claimed deliveries have conflicting batch identities"
      end

      batch ||= recover_legacy_projection_batch(deliveries, identity)
      unless (deliveries.map(&:id) - batch.delivery_ids).empty?
        raise TelemetryProjectionBatch::InvalidPayload, "Claimed deliveries are missing from the persisted batch"
      end

      TelemetryDelivery.assign_batch_key_batch!(deliveries, batch_key: batch.batch_key)
      send_projection_batch(batch, deliveries)
    rescue StandardError => error
      fail_batch!(deliveries, error)
    end

    def recover_legacy_projection_batch(deliveries, identity)
      # Older releases did not persist the body and could ACK only a prefix.
      # Rebuild the full original membership, including completed rows, and
      # verify its UUID digest before ever reusing the old deduplication token.
      members = TelemetryDelivery.where(identity).order(:id).includes(:telemetry_outbox_event)
        .limit(TelemetryProjectionBatch::MAX_ROWS + 1).to_a
      unless members.length <= TelemetryProjectionBatch::MAX_ROWS && generated_batch_key(members) == identity.fetch(:batch_key)
        raise TelemetryProjectionBatch::InvalidPayload, "The original legacy batch membership is unavailable"
      end
      owned_ids = deliveries.map(&:id)
      unless members.all? { |member| member.completed? || owned_ids.include?(member.id) }
        raise TelemetryDelivery::BatchOwnershipLost, "Another owner still holds part of the legacy batch"
      end

      preload_sources(members)
      rows = members.map do |member|
        ensure_project_active!(member)
        record = source_record!(member)
        ensure_legacy_source_unchanged!(member, record)
        attributes = clickhouse_attributes(member, record)
        raise TelemetryProjectionBatch::InvalidPayload, "A legacy batch member is no longer projectable" unless attributes

        attributes
      end
      payload = "#{rows.map(&:to_json).join("\n")}\n"
      @metrics.count(:legacy_batch_snapshots)
      TelemetryProjectionBatch.prepare!(deliveries: deliveries, members: members, batch_key: identity.fetch(:batch_key), payload: payload)
    end

    def ensure_legacy_source_unchanged!(delivery, record)
      outbox = delivery.telemetry_outbox_event
      service = record.context.to_h.with_indifferent_access[:service]
      project_fallback_changed = service.blank? && record.project.updated_at > record.created_at
      if record.updated_at > record.created_at || outbox.updated_at > outbox.created_at || project_fallback_changed
        raise TelemetryProjectionBatch::InvalidPayload, "Legacy batch data changed without a saved payload; inspect before replay"
      end
    end

    def send_projection_batch(batch, deliveries)
      raise ClickhouseDisabled, "ClickHouse writes are disabled" unless clickhouse_client.enabled?

      payload = batch.payload
      Project.transaction(requires_new: true) do
        project = Project.lock("FOR SHARE").find_by(id: batch.project_id)
        raise ProjectPurging, "Project purge is pending" if project.nil? || project.purge_pending?
        return unless begin_external_write?(deliveries)

        @metrics.measure(:insert) do
          SelfReportingGuard.suppress do
            if batch.destination == "clickhouse_event"
              clickhouse_client.insert_event_payload!(payload, deduplication_token: batch.batch_key, gzip: true)
            else
              clickhouse_client.insert_span_payload!(payload, deduplication_token: batch.batch_key, gzip: true)
            end
          end
        end
      end
      completed_ids = @metrics.measure(:acknowledgement) { batch.acknowledge!(deliveries, at: now) }
      @completed += completed_ids.length
      @metrics.count(:lease_conflicts, deliveries.length - completed_ids.length)
    end

    def stable_batch_key(deliveries)
      existing = deliveries.filter_map(&:batch_key).uniq
      return existing.first if existing.one?
      raise ProjectionError, "Claimed deliveries have conflicting batch identities" if existing.many?

      generated_batch_key(deliveries)
    end

    def generated_batch_key(deliveries)
      raise TelemetryProjectionBatch::InvalidPayload, "A projection batch cannot be empty" if deliveries.empty?

      digest = Digest::SHA256.hexdigest(deliveries.map(&:uuid).sort.join("|"))
      "logister-v1-#{deliveries.first.destination}-#{digest}"
    end

    def source_record!(delivery)
      @metrics.measure(:source_load) do
        (@projection_sources ? @projection_sources.fetch(delivery) : delivery.telemetry_outbox_event.source_record) ||
          raise(MissingSourceRecord, "Accepted #{delivery.telemetry_outbox_event.record_type} is no longer available")
      end
    end

    def ensure_project_active!(delivery)
      project = @projection_sources ? @projection_sources.project_for(delivery) : delivery.project.reload
      raise ProjectPurging, "Project purge is pending" if project.nil? || project.purge_pending?
    end

    def send_notifications?(delivery)
      delivery.telemetry_outbox_event.metadata.to_h.dig("routing", "send_notifications") != false
    end

    def complete!(delivery)
      start_deliveries!([ delivery ])
      completed = @metrics.measure(:acknowledgement) { delivery.mark_completed!(lease_token: delivery.lease_token, at: now) }
      unless completed
        @metrics.count(:lease_conflicts)
        return
      end

      @completed += 1
    end

    def fail!(delivery, error, terminal: false)
      start_deliveries!([ delivery ])
      retryable = !terminal && retryable_error?(error)
      marked = delivery.mark_failed!(
        error,
        lease_token: delivery.lease_token,
        terminal: !retryable,
        at: now
      )
      return unless marked

      delivery.terminal_failed? ? @terminal_failed += 1 : @retried += 1
    end

    def retryable_error?(error)
      return error.retryable? if error.respond_to?(:retryable?)

      true
    end

    def fail_batch!(deliveries, error)
      return unless deliveries

      start_deliveries!(deliveries)
      deliveries.each do |delivery|
        # If failure bookkeeping outlives the run, leave the remaining leases
        # for recovery. They were attempted, so do not refund those attempts.
        break unless continue_work?

        fail!(delivery, error, terminal: poison_error?(error))
      end
    end

    def continue_work?
      !@run || @run.continue?
    end

    def start_deliveries!(deliveries)
      @started_delivery_ids&.merge(deliveries.map(&:id))
    end

    def begin_external_write?(deliveries)
      if @run
        return false unless @run.continue?(force: true)

        TelemetryDelivery.renew_batch_lease!(deliveries, at: now)
      end
      start_deliveries!(deliveries)
      true
    end

    def poison_error?(error)
      error.is_a?(MissingSourceRecord) || error.is_a?(PayloadTooLarge) ||
        error.is_a?(ProjectPurging) || error.is_a?(InvalidProjection) || error.is_a?(TelemetryProjectionBatch::InvalidPayload)
    end

    def report_clickhouse_failure(item, error)
      return unless item

      record = item.fetch(:record)
      if record.is_a?(TraceSpan)
        ClickhouseFailureReporter.report_span_failure(record, error)
      else
        ClickhouseFailureReporter.report_event_failure(record, error)
      end
    rescue StandardError => report_error
      Rails.logger.warn("telemetry_projector_failure_reporting_error error=#{report_error.class}: #{report_error.message}")
    end
  end
end

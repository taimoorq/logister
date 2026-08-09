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

    def initialize(clickhouse_client: ClickhouseClient.new, now: -> { Time.current })
      @clickhouse_client = clickhouse_client
      @now = now
      reset_counts
    end

    def call(limit: MAX_BATCH_ROWS)
      reset_counts
      deliveries = TelemetryDelivery.claim_batch(limit: limit, now: now)
      @claimed = deliveries.length
      return result if deliveries.empty?

      if deliveries.first.destination.in?(TelemetryDelivery::CLICKHOUSE_DESTINATIONS)
        project_clickhouse(deliveries)
      else
        deliveries.each { |delivery| project_single(delivery) }
      end
      result
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
      pairs = deliveries.filter_map do |delivery|
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

      byte_bounded_chunks(pairs).each { |chunk| insert_clickhouse_chunk(chunk) }
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
      deliveries = chunk.map { |item| item.fetch(:delivery) }
      project_ids = deliveries.map(&:project_id).uniq
      raise ProjectionError, "A ClickHouse batch cannot span projects" unless project_ids.one?

      batch_key = stable_batch_key(deliveries)
      deliveries.each { |delivery| delivery.assign_batch_key!(batch_key) }
      deliveries.each { |delivery| ensure_project_active!(delivery) }
      rows = chunk.map { |item| item.fetch(:attributes) }

      # Serialize every external write with ProjectPurgeRequest's tombstone lock.
      # A writer that acquired the row first finishes before the tombstone; a
      # writer that arrives later observes purge_requested_at and cannot recreate
      # ClickHouse data after the purge mutation has been verified.
      Project.transaction(requires_new: true) do
        project = Project.lock.find_by(id: project_ids.first)
        raise ProjectPurging, "Project purge is pending" if project.nil? || project.purge_pending?

        SelfReportingGuard.suppress do
          if deliveries.first.destination == "clickhouse_event"
            clickhouse_client.insert_events!(rows, deduplication_token: batch_key, gzip: true)
          else
            clickhouse_client.insert_spans!(rows, deduplication_token: batch_key, gzip: true)
          end
        end
      end
      deliveries.each { |delivery| complete!(delivery) }
    rescue StandardError => error
      deliveries&.each { |delivery| fail!(delivery, error, terminal: poison_error?(error)) }
      report_clickhouse_failure(chunk&.first, error)
    end

    def stable_batch_key(deliveries)
      existing = deliveries.filter_map(&:batch_key).uniq
      return existing.first if existing.one?
      raise ProjectionError, "Claimed deliveries have conflicting batch identities" if existing.many?

      digest = Digest::SHA256.hexdigest(deliveries.map(&:uuid).sort.join("|"))
      "logister-v1-#{deliveries.first.destination}-#{digest}"
    end

    def source_record!(delivery)
      delivery.telemetry_outbox_event.source_record ||
        raise(MissingSourceRecord, "Accepted #{delivery.telemetry_outbox_event.record_type} is no longer available")
    end

    def ensure_project_active!(delivery)
      project = delivery.project.reload
      raise ProjectPurging, "Project purge is pending" if project.purge_pending?
    end

    def send_notifications?(delivery)
      delivery.telemetry_outbox_event.metadata.to_h.dig("routing", "send_notifications") != false
    end

    def complete!(delivery)
      return unless delivery.mark_completed!(lease_token: delivery.lease_token, at: now)

      @completed += 1
    end

    def fail!(delivery, error, terminal: false)
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

    def poison_error?(error)
      error.is_a?(MissingSourceRecord) || error.is_a?(PayloadTooLarge) ||
        error.is_a?(ProjectPurging) || error.is_a?(InvalidProjection)
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

# frozen_string_literal: true

module Logister
  class ClickhouseEventBackfill
    DEFAULT_BATCH_SIZE = 250
    DEFAULT_MAX_WATERMARK_BUCKETS = 50_000

    attr_reader :watermark_results

    def initialize(scope:, client: nil, batch_size: DEFAULT_BATCH_SIZE,
                   watermark_reconciler: ClickhouseBackfillWatermarkReconciler,
                   coverage_from: nil, coverage_to: nil, project_ids: nil,
                   source_complete: false, max_watermark_buckets: DEFAULT_MAX_WATERMARK_BUCKETS)
      @scope = scope
      @client = client || ClickhouseClient.new
      @owns_client = client.nil?
      @batch_size = batch_size.to_i.positive? ? batch_size.to_i : DEFAULT_BATCH_SIZE
      @watermark_reconciler = watermark_reconciler
      @coverage_from = coverage_from&.to_time&.utc
      @coverage_to = coverage_to&.to_time&.utc
      @coverage_project_ids = Array(project_ids).map(&:to_i).select(&:positive?).uniq
      @source_complete = source_complete == true
      @max_watermark_buckets = Integer(max_watermark_buckets)
      @watermark_results = []
    end

    def call
      return 0 unless @client.enabled?

      validate_explicit_reconciliation_bound!
      inserted = 0
      bucket_keys = {}
      @scope.in_batches(of: @batch_size) do |batch|
        events = batch.includes(:project).to_a.reject { |event| event.project.purge_pending? }
        events.each do |event|
          bucket_keys[[ event.project_id, event.event_type, event.occurred_at.utc.beginning_of_hour ]] = true
        end
        rows = events.map do |event|
          EventIngestor.new(event:, request_context: {}, clickhouse_client: @client).attributes
        end
        existing_keys = existing_event_keys(rows)
        rows.reject! do |row|
          existing_keys.key?([ row.fetch(:project_id).to_i, row.fetch(:event_id).to_s ])
        end
        next if rows.empty?

        inserted += insert_active_rows(rows)
      end
      @watermark_results = if @source_complete
        reconcile_watermarks(expanded_bucket_keys(bucket_keys.keys))
      else
        []
      end
      inserted
    ensure
      close_owned_client
    end

    private

    def close_owned_client
      @client.close if @owns_client
    rescue StandardError => error
      Rails.logger.warn("clickhouse_event_backfill_close_error error=#{error.class}: #{error.message}")
    end

    def insert_active_rows(rows)
      inserted = 0
      Project.transaction(requires_new: true) do
        active_project_ids = Project.where(id: rows.map { |row| row.fetch(:project_id) }, purge_requested_at: nil)
          .order(:id)
          .lock
          .pluck(:id)
        active_rows = rows.select { |row| active_project_ids.include?(row.fetch(:project_id).to_i) }
        next if active_rows.empty?

        @client.insert_events!(active_rows)
        inserted = active_rows.length
      end
      inserted
    end

    def expanded_bucket_keys(touched_keys)
      keys = touched_keys.index_with(true)
      project_ids = @coverage_project_ids.presence || touched_keys.map(&:first).uniq
      started_at = @coverage_from || touched_keys.map(&:last).min
      ended_at = @coverage_to || (touched_keys.map(&:last).max&.+(1.hour))
      return keys.keys if project_ids.empty? || started_at.nil? || ended_at.nil?

      cursor = started_at.beginning_of_hour
      ensure_bucket_limit!(project_ids, cursor, ended_at)
      while cursor < ended_at
        project_ids.each do |project_id|
          ClickhouseCoverage::EVENT_SIGNALS.each do |signal|
            keys[[ project_id, signal, cursor ]] = true
          end
        end
        cursor += 1.hour
      end
      keys.keys
    end

    def validate_explicit_reconciliation_bound!
      return unless @source_complete && @coverage_from && @coverage_to && @coverage_project_ids.any?

      ensure_bucket_limit!(@coverage_project_ids, @coverage_from.beginning_of_hour, @coverage_to)
    end

    def ensure_bucket_limit!(project_ids, started_at, ended_at)
      estimated_bucket_count = project_ids.length * ClickhouseCoverage::EVENT_SIGNALS.length *
        [ ((ended_at - started_at) / 1.hour).ceil, 0 ].max
      return if estimated_bucket_count <= @max_watermark_buckets

      raise ArgumentError,
        "Event watermark reconciliation requires #{estimated_bucket_count} buckets; " \
        "maximum is #{@max_watermark_buckets}"
    end

    def reconcile_watermarks(bucket_keys)
      bucket_keys.sort_by { |project_id, signal, bucket| [ project_id, signal, bucket ] }.map do |project_id, signal, bucket|
        @watermark_reconciler.call(
          client: @client,
          project_id: project_id,
          signal: signal,
          bucket_start_at: bucket,
          source_complete: @source_complete
        )
      end
    end

    def existing_event_keys(rows)
      return {} if rows.empty?

      values = rows.map do |row|
        event_id = TelemetryIdentity.normalize_uuid(row.fetch(:event_id)) || raise(ArgumentError, "Invalid event UUID")
        project_id = Integer(row.fetch(:project_id))
        checksum = Integer(row.fetch(:identity_checksum))
        projection_version = Integer(row.fetch(:projection_version))
        "(#{project_id}, toUUID('#{event_id}'), toUInt128('#{checksum}'), #{projection_version})"
      end.join(", ")
      @client.select_rows!(<<~SQL.squish).to_h do |row|
        SELECT project_id, toString(event_id) AS event_id
        FROM #{@client.events_table_name}
        WHERE (project_id, event_id, identity_checksum, projection_version) IN (#{values})
      SQL
        [ [ row.fetch("project_id").to_i, row.fetch("event_id").to_s ], true ]
      end
    end
  end
end

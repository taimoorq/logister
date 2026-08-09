# frozen_string_literal: true

module Logister
  class ClickhouseReadRouter
    Result = Data.define(:payload, :source, :coverage, :fallback_reason, :reconciliation, :postgres_coverage) do
      def clickhouse?
        source == "clickhouse"
      end

      def partial?
        source == "postgresql" && postgres_coverage.present? && !postgres_coverage.complete?
      end

      def diagnostics
        {
          source: source,
          fallback_reason: fallback_reason,
          coverage: coverage&.to_h,
          reconciliation: reconciliation&.to_h,
          partial: partial?,
          fallback_coverage: postgres_coverage&.to_h
        }.compact
      end
    end

    class << self
      def call(...)
        new(...).call
      end
    end

    def initialize(project_ids:, signals:, from:, to:, clickhouse:, postgres:,
                   client: nil, coverage: nil,
                   coverage_service: ClickhouseCoverage,
                   postgres_coverage_service: Logister::PostgresRetentionCoverage,
                   reconciler: ClickhouseDualReadReconciler.new)
      @project_ids = Array(project_ids).map(&:to_i).select(&:positive?).uniq.sort
      @signals = Array(signals).map(&:to_s).uniq.sort
      @started_at = from.to_time.utc
      @ended_at = to.to_time.utc
      @clickhouse = clickhouse
      @postgres = postgres
      @client = client || ClickhouseClient.new
      @owns_client = client.nil?
      @coverage = coverage
      @coverage_service = coverage_service
      @postgres_coverage_service = postgres_coverage_service
      @reconciler = reconciler
    end

    def call
      return postgres_result("clickhouse_read_disabled") unless @client.read_enabled?

      coverage = @coverage || @coverage_service.call(
        project_ids: @project_ids,
        signals: @signals,
        from: @started_at,
        to: @ended_at
      )
      @coverage = coverage
      return postgres_result(coverage.reason, coverage:) unless coverage.complete?

      payload = begin
        @clickhouse.arity.zero? ? @clickhouse.call : @clickhouse.call(@client)
      rescue StandardError => error
        Rails.logger.warn("ClickHouse analytical read failed: #{error.class} #{error.message}")
        return postgres_result("clickhouse_query_failed", coverage:, error:)
      end
      reconciliation = reconcile(payload)
      Result.new(payload, "clickhouse", coverage, nil, reconciliation, nil)
    ensure
      @client.close if @owns_client
    end

    private

    def postgres_result(reason, coverage: @coverage, error: nil)
      payload = @postgres.call
      reason = "#{reason}: #{error.class}" if error
      postgres_coverage = @postgres_coverage_service.call(
        project_ids: @project_ids,
        signals: @signals,
        from: @started_at,
        to: @ended_at
      )
      Result.new(payload, "postgresql", coverage, reason, @reconciler.skipped, postgres_coverage)
    end

    def reconcile(primary)
      return @reconciler.skipped unless @reconciler.sampled?(sample_key)

      @reconciler.compare(
        primary: primary,
        shadow: @postgres.call,
        context: {
          project_ids: @project_ids,
          signals: @signals,
          started_at: @started_at.iso8601,
          ended_at: @ended_at.iso8601
        }
      )
    end

    def sample_key
      [ @project_ids, @signals, @started_at.beginning_of_hour, @ended_at.beginning_of_hour ].join(":")
    end
  end
end

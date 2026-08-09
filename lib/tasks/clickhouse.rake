# frozen_string_literal: true

require "json"

namespace :logister do
  namespace :clickhouse do
    namespace :events do
      desc "Idempotently backfill retained PostgreSQL events into ClickHouse"
      task :backfill, [ :from, :to ] => :environment do |_task, args|
        abort "Refusing to backfill without CONFIRM=backfill" unless ENV["CONFIRM"] == "backfill"
        abort "Both from and to are required for bounded backfill" unless args[:from].present? && args[:to].present?

        from = Time.zone.parse(args[:from])
        to = Time.zone.parse(args[:to])
        abort "Backfill to must be later than from" unless to > from
        project_scope = Project.where(purge_requested_at: nil)
        if ENV["PROJECT_UUID"].present?
          project_scope = project_scope.where(uuid: ENV["PROJECT_UUID"])
          abort "PROJECT_UUID does not identify an active project" unless project_scope.exists?
        end
        project_ids = project_scope.pluck(:id)
        scope = IngestEvent.where(project_id: project_ids, occurred_at: from...to)
        source_complete_from = Time.zone.parse(ENV["SOURCE_COMPLETE_FROM"]) if ENV["SOURCE_COMPLETE_FROM"].present?
        abort "SOURCE_COMPLETE_FROM must be at or before from" if source_complete_from && source_complete_from > from
        source_complete = source_complete_from.present? && source_complete_from <= from
        max_watermark_buckets = ENV["ALLOW_LARGE_BACKFILL"] == "1" ? 10_000_000 :
          Logister::ClickhouseEventBackfill::DEFAULT_MAX_WATERMARK_BUCKETS
        backfill = Logister::ClickhouseEventBackfill.new(
          scope: scope,
          coverage_from: from,
          coverage_to: to,
          project_ids: project_ids,
          source_complete: source_complete,
          max_watermark_buckets: max_watermark_buckets
        )
        inserted = backfill.call

        puts JSON.pretty_generate(
          inserted_events: inserted,
          from: from&.iso8601,
          to: to&.iso8601,
          source_complete_from: source_complete_from&.iso8601,
          watermark_certification: source_complete ? "attempted" : "skipped_source_baseline_required",
          watermark_buckets: backfill.watermark_results.map(&:status).tally
        )
      end
    end

    namespace :spans do
      desc "Idempotently backfill retained PostgreSQL spans into ClickHouse"
      task :backfill, [ :from, :to ] => :environment do |_task, args|
        abort "Refusing to backfill without CONFIRM=backfill" unless ENV["CONFIRM"] == "backfill"
        abort "Both from and to are required for bounded backfill" unless args[:from].present? && args[:to].present?

        from = Time.zone.parse(args[:from])
        to = Time.zone.parse(args[:to])
        abort "Backfill to must be later than from" unless to > from
        project_scope = Project.where(purge_requested_at: nil)
        if ENV["PROJECT_UUID"].present?
          project_scope = project_scope.where(uuid: ENV["PROJECT_UUID"])
          abort "PROJECT_UUID does not identify an active project" unless project_scope.exists?
        end
        project_ids = project_scope.pluck(:id)
        scope = TraceSpan.where(project_id: project_ids, started_at: from...to)
        source_complete_from = Time.zone.parse(ENV["SOURCE_COMPLETE_FROM"]) if ENV["SOURCE_COMPLETE_FROM"].present?
        abort "SOURCE_COMPLETE_FROM must be at or before from" if source_complete_from && source_complete_from > from
        source_complete = source_complete_from.present? && source_complete_from <= from
        max_watermark_buckets = ENV["ALLOW_LARGE_BACKFILL"] == "1" ? 10_000_000 :
          Logister::ClickhouseSpanBackfill::DEFAULT_MAX_WATERMARK_BUCKETS
        backfill = Logister::ClickhouseSpanBackfill.new(
          scope: scope,
          coverage_from: from,
          coverage_to: to,
          project_ids: project_ids,
          source_complete: source_complete,
          max_watermark_buckets: max_watermark_buckets
        )
        inserted = backfill.call

        puts JSON.pretty_generate(
          inserted_spans: inserted,
          from: from&.iso8601,
          to: to&.iso8601,
          source_complete_from: source_complete_from&.iso8601,
          watermark_certification: source_complete ? "attempted" : "skipped_source_baseline_required",
          watermark_buckets: backfill.watermark_results.map(&:status).tally
        )
      end
    end

    namespace :schema do
      desc "Print ClickHouse schema readiness for Logister analytics tables"
      task status: :environment do
        client = Logister::ClickhouseClient.new
        puts JSON.pretty_generate(client.schema_status)
      ensure
        client&.close
      end

      desc "Create missing ClickHouse objects and repair known compatible schema drift"
      task load: :environment do
        puts JSON.pretty_generate(Logister::ClickhouseSchemaRepairer.call)
      end

      desc "Idempotently repair the configured ClickHouse schema"
      task repair: :environment do
        puts JSON.pretty_generate(Logister::ClickhouseSchemaRepairer.call)
      end
    end

    namespace :generation do
      desc "Record the currently configured ClickHouse store in the permanent purge inventory"
      task register: :environment do
        abort "Refusing to register a store generation without CONFIRM=register" unless ENV["CONFIRM"] == "register"

        locator = TelemetryStoreGeneration.clickhouse_locator
        generation = TelemetryStoreGeneration.register_locator!(locator)
        puts JSON.pretty_generate(
          generation_id: generation.generation_id,
          locator: generation.locator.except("generation_id"),
          first_seen_at: generation.first_seen_at.utc.iso8601,
          last_seen_at: generation.last_seen_at.utc.iso8601
        )
      end
    end
  end
end

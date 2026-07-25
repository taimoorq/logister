# frozen_string_literal: true

require "json"

namespace :logister do
  namespace :clickhouse do
    namespace :events do
      desc "Idempotently backfill retained PostgreSQL events into ClickHouse"
      task :backfill, [ :from, :to ] => :environment do |_task, args|
        abort "Refusing to backfill without CONFIRM=backfill" unless ENV["CONFIRM"] == "backfill"

        scope = IngestEvent.all
        from = Time.zone.parse(args[:from]) if args[:from].present?
        to = Time.zone.parse(args[:to]) if args[:to].present?
        scope = scope.where("occurred_at >= ?", from) if from
        scope = scope.where("occurred_at < ?", to) if to
        inserted = Logister::ClickhouseEventBackfill.new(scope: scope).call

        puts JSON.pretty_generate(inserted_events: inserted, from: from&.iso8601, to: to&.iso8601)
      end
    end

    namespace :schema do
      desc "Print ClickHouse schema readiness for Logister analytics tables"
      task status: :environment do
        puts JSON.pretty_generate(Logister::ClickhouseClient.new.schema_status)
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
  end
end

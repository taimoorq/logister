# frozen_string_literal: true

require "json"

namespace :logister do
  namespace :postgres do
    namespace :partitioning do
      desc "Show ingest_events partitioning mirror status"
      task status: :environment do
        puts JSON.pretty_generate(Logister::IngestEventsPartitioning.new.status)
      end

      desc "Backfill ingest_events_partitioned. Defaults to dry run. Use CONFIRM=backfill DRY_RUN=false to write."
      task :backfill, [ :from, :to ] => :environment do |_task, args|
        dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "true"))
        abort "Refusing to backfill without CONFIRM=backfill" if !dry_run && ENV["CONFIRM"] != "backfill"

        result = Logister::IngestEventsPartitioning.new.backfill(
          from: args[:from].presence || ENV["FROM"].presence,
          to: args[:to].presence || ENV["TO"].presence,
          batch_size: ENV.fetch("BATCH_SIZE", Logister::IngestEventsPartitioning::DEFAULT_BATCH_SIZE),
          dry_run: dry_run
        )

        puts JSON.pretty_generate(result)
      end

      desc "Validate ingest_events_partitioned against ingest_events"
      task validate: :environment do
        puts JSON.pretty_generate(Logister::IngestEventsPartitioning.new.validate)
      end

      desc "Run preflight checks for the partitioned ingest_events cutover"
      task cutover_preflight: :environment do
        puts JSON.pretty_generate(Logister::IngestEventsPartitioning.new.cutover_preflight)
      end

      desc "Cut over ingest_events to the partitioned shadow table. Requires CONFIRM=cutover."
      task cutover: :environment do
        abort "Refusing to cut over without CONFIRM=cutover" unless ENV["CONFIRM"] == "cutover"

        result = Logister::IngestEventsPartitioning.new.cutover(
          lock_timeout: ENV.fetch("LOCK_TIMEOUT", "30s")
        )

        puts JSON.pretty_generate(result)
      end

      desc "Compare post-cutover partitioned ingest_events against ingest_events_unpartitioned_backup"
      task validate_cutover_copy: :environment do
        puts JSON.pretty_generate(Logister::IngestEventsPartitioning.new.validate_cutover_copy)
      end

      desc "Validate post-cutover composite foreign keys. Requires CONFIRM=validate_constraints."
      task validate_cutover_constraints: :environment do
        unless ENV["CONFIRM"] == "validate_constraints"
          abort "Refusing to validate cutover constraints without CONFIRM=validate_constraints"
        end

        puts JSON.pretty_generate(Logister::IngestEventsPartitioning.new.validate_cutover_constraints)
      end

      desc "Ensure future monthly ingest_events partitions exist"
      task ensure_future_partitions: :environment do
        result = Logister::IngestEventsPartitioning.new.ensure_future_partitions(
          months_ahead: ENV.fetch("MONTHS_AHEAD", Logister::IngestEventsPartitioning::DEFAULT_FUTURE_PARTITION_MONTHS)
        )
        puts JSON.pretty_generate(result)
      end
    end
  end
end

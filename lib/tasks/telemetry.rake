# frozen_string_literal: true

require "json"

namespace :logister do
  namespace :telemetry do
    desc "Archive telemetry to configured Active Storage service: logister:telemetry:archive[ingest_events,30]"
    task :archive, [ :record_type, :days ] => :environment do |_task, args|
      record_type = args[:record_type].presence || ENV.fetch("RECORD_TYPE", "ingest_events")
      days = Integer(args[:days].presence || ENV.fetch("DAYS", "30"))
      before = Time.current - days.days

      result = Logister::TelemetryArchiveExporter.new(
        record_type: record_type,
        before: before,
        batch_size: Integer(ENV.fetch("BATCH_SIZE", Logister::TelemetryArchiveExporter::DEFAULT_BATCH_SIZE)),
        prefix: ENV.fetch("LOGISTER_ARCHIVE_PREFIX", "telemetry"),
        dry_run: ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false"))
      ).call

      puts JSON.pretty_generate(result)
    end

    desc "Prune archived hot telemetry older than DAYS. Requires CONFIRM=prune."
    task :prune_hot, [ :days ] => :environment do |_task, args|
      unless ENV["CONFIRM"] == "prune"
        abort "Refusing to prune without CONFIRM=prune"
      end

      days = Integer(args[:days].presence || ENV.fetch("DAYS", "30"))
      before = Time.current - days.days
      non_error_events = IngestEvent.where("created_at < ?", before)
                                    .where.not(event_type: IngestEvent.event_types.fetch("error"))
                                    .where(error_group_id: nil)
      spans = TraceSpan.where("created_at < ?", before)

      result = {
        before: before.utc.iso8601,
        deleted_non_error_events: non_error_events.delete_all,
        deleted_trace_spans: spans.delete_all
      }

      puts JSON.pretty_generate(result)
    end
  end
end

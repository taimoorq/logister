# frozen_string_literal: true

require "json"

namespace :logister do
  namespace :telemetry do
    desc "Archive one project's telemetry with a verified manifest: logister:telemetry:archive[ingest_events,30,PROJECT_UUID]"
    task :archive, [ :record_type, :days, :project_uuid ] => :environment do |_task, args|
      record_type = args[:record_type].presence || ENV.fetch("RECORD_TYPE", "ingest_events")
      days = Integer(args[:days].presence || ENV.fetch("DAYS", "30"))
      project_uuid = args[:project_uuid].presence || ENV["PROJECT_UUID"].presence
      abort "PROJECT_UUID is required; untracked global archive objects are disabled" if project_uuid.blank?

      project = Project.find_by(uuid: project_uuid)
      abort "No project found for #{project_uuid}" unless project
      abort "Project purge is pending for #{project_uuid}" if project.purge_pending?
      before = Time.current - days.days

      result = Logister::TelemetryArchiveExporter.new(
        record_type: record_type,
        project: project,
        scope: "manual_#{record_type}",
        before: before,
        batch_size: Integer(ENV.fetch("BATCH_SIZE", Logister::TelemetryArchiveExporter::DEFAULT_BATCH_SIZE)),
        prefix: ENV.fetch("LOGISTER_ARCHIVE_PREFIX", "telemetry"),
        dry_run: ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false")),
        object_limit: Integer(
          ENV.fetch(
            "LOGISTER_RETENTION_OBJECTS_PER_ATTEMPT",
            Logister::ProjectRetentionRunRunner::DEFAULT_OBJECTS_PER_ATTEMPT
          )
        )
      ).call

      puts JSON.pretty_generate(result)
    end

    desc "Disabled legacy global prune; use the delivery-safe per-project retention task."
    task :prune_hot, [ :days ] => :environment do
      abort <<~MESSAGE.squish
        logister:telemetry:prune_hot is disabled because a global delete cannot
        honor project archive policy or unfinished outbox deliveries. Use
        logister:telemetry:retention with DRY_RUN=true first, then run with
        DRY_RUN=false CONFIRM=retention.
      MESSAGE
    end

    desc "Run per-project telemetry retention. Defaults to dry run. Use DRY_RUN=false CONFIRM=retention to delete."
    task :retention, [ :project_uuid ] => :environment do |_task, args|
      dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "true"))
      abort "Refusing to delete without CONFIRM=retention" if !dry_run && ENV["CONFIRM"] != "retention"

      project_uuid = args[:project_uuid].presence || ENV["PROJECT_UUID"].presence
      projects = project_uuid.present? ? Project.where(uuid: project_uuid) : Project.all
      abort "No project found for #{project_uuid}" if project_uuid.present? && projects.blank?

      results = []
      projects.find_each do |project|
        if dry_run
          results << Logister::ProjectRetentionRunner.new(
            project: project,
            batch_size: Integer(ENV.fetch("BATCH_SIZE", Logister::ProjectRetentionRunner::DEFAULT_BATCH_SIZE)),
            dry_run: true
          ).call
        else
          outcome = Logister::ProjectRetentionRunCoordinator.create_or_find!(
            project: project,
            scheduled_for: Time.current.change(usec: 0),
            dry_run: false,
            trigger_kind: "manual"
          )
          ProjectRetentionJob.perform_later(project.id, dry_run: false, run_id: outcome.run.id)
          results << {
            project_id: project.id,
            project_uuid: project.uuid,
            run_id: outcome.run.id,
            status: outcome.run.status,
            created: outcome.created,
            enqueued: true
          }
        end
      end

      puts JSON.pretty_generate(results)
    end
  end
end

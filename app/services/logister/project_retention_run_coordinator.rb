# frozen_string_literal: true

module Logister
  class ProjectRetentionRunCoordinator
    Result = Data.define(:run, :created)

    def self.create_or_find!(project:, scheduled_for:, dry_run:, trigger_kind:)
      new(
        project: project,
        scheduled_for: scheduled_for,
        dry_run: dry_run,
        trigger_kind: trigger_kind
      ).create_or_find!
    end

    def initialize(project:, scheduled_for:, dry_run:, trigger_kind:)
      @project = project
      @scheduled_for = scheduled_for.in_time_zone("UTC")
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
      @trigger_kind = trigger_kind.to_s
    end

    def create_or_find!
      run_key = ProjectRetentionRun.run_key_for(
        project_id: @project.id,
        scheduled_for: @scheduled_for,
        dry_run: @dry_run
      )
      existing = ProjectRetentionRun.find_by(run_key: run_key)
      return Result.new(run: existing, created: false) if existing

      if !@dry_run && (active = @project.retention_runs.active.first)
        return Result.new(run: active, created: false)
      end

      policy = policy_for_snapshot
      run = @project.retention_runs.create!(
        run_key: run_key,
        trigger_kind: @trigger_kind,
        dry_run: @dry_run,
        scheduled_for: @scheduled_for,
        status: "queued",
        phase: "planning",
        available_at: Time.current,
        policy_snapshot: policy_snapshot(policy),
        cutoff_snapshot: cutoff_snapshot(policy)
      )
      Result.new(run: run, created: true)
    rescue ActiveRecord::RecordNotUnique
      existing = ProjectRetentionRun.find_by(run_key: run_key)
      existing ||= @project.retention_runs.active.first unless @dry_run
      raise unless existing

      Result.new(run: existing, created: false)
    end

    private

    def policy_for_snapshot
      return @project.retention_policy || @project.build_retention_policy if @dry_run

      ProjectRetentionPolicy.for(project: @project)
    end

    def policy_snapshot(policy)
      {
        "hot_retention_days" => policy.hot_retention_days,
        "trace_retention_days" => policy.trace_retention_days,
        "error_retention_days" => policy.error_retention_days,
        "archive_enabled" => policy.archive_enabled?,
        "archive_before_delete" => policy.archive_before_delete?,
        "captured_at" => Time.current.utc.iso8601(6)
      }
    end

    def cutoff_snapshot(policy)
      error_cutoff = if policy.error_retention_days.present?
        (@scheduled_for - policy.error_retention_days.days).utc.iso8601(6)
      end
      {
        "hot_events" => (@scheduled_for - policy.hot_retention_days.days).utc.iso8601(6),
        "trace_spans" => (@scheduled_for - policy.trace_retention_days.days).utc.iso8601(6),
        "error_events" => error_cutoff
      }
    end
  end
end

# frozen_string_literal: true

class ProjectArchiveOverview
  RETENTION_SWEEP_HOUR_UTC = 2

  STATUS_LABELS = {
    archive_gap: "Archive gap",
    awaiting_cleanup: "Awaiting cleanup",
    covered: "Covered",
    failed: "Failed",
    healthy: "Protected before deletion",
    kept_forever: "Kept forever",
    needs_attention: "Needs attention",
    no_archive_yet: "No archive yet",
    no_candidates: "No candidates",
    not_archiving: "Not archiving",
    archive_not_required: "Archiving enabled, deletion not protected"
  }.freeze

  STATUS_TONES = {
    archive_gap: :danger,
    awaiting_cleanup: :warning,
    covered: :success,
    failed: :danger,
    healthy: :success,
    kept_forever: :info,
    needs_attention: :danger,
    no_archive_yet: :warning,
    no_candidates: :muted,
    not_archiving: :muted,
    archive_not_required: :warning
  }.freeze

  CoverageRow = Struct.new(
    :key,
    :label,
    :description,
    :retention_days,
    :cutoff_at,
    :archive_scope,
    :archived_through_at,
    :last_archive,
    :last_failure,
    :last_rows,
    :last_deleted,
    :candidate_count,
    :status,
    :note,
    keyword_init: true
  ) do
    def retention_forever?
      retention_days.blank?
    end

    def archive_gap?
      status == :archive_gap
    end

    def status_label
      ProjectArchiveOverview::STATUS_LABELS.fetch(status)
    end

    def status_tone
      ProjectArchiveOverview::STATUS_TONES.fetch(status)
    end
  end

  def initialize(project:, policy:, now: Time.current)
    @project = project
    @policy = policy
    @now = now
    @last_retention_result = policy.last_retention_result.is_a?(Hash) ? policy.last_retention_result.with_indifferent_access : {}
  end

  attr_reader :project, :policy, :now

  def archive_guard_enabled?
    policy.archive_enabled? && policy.archive_before_delete?
  end

  def last_cleanup_at
    policy.last_retention_run_at
  end

  def last_successful_archive
    @last_successful_archive ||= project.telemetry_archives.completed.recent_first.first
  end

  def last_failed_archive
    @last_failed_archive ||= project.telemetry_archives.failed.recent_first.first
  end

  def next_sweep_at
    candidate = now.utc.change(hour: RETENTION_SWEEP_HOUR_UTC, min: 0, sec: 0)
    candidate > now.utc ? candidate : candidate + 1.day
  end

  def health_status
    @health_status ||= begin
      if !policy.archive_enabled?
        :not_archiving
      elsif !policy.archive_before_delete?
        :archive_not_required
      elsif last_failed_archive.present? && (last_successful_archive.blank? || last_failed_archive.created_at >= last_successful_archive.created_at)
        :needs_attention
      elsif coverage_rows.any?(&:archive_gap?)
        :archive_gap
      else
        :healthy
      end
    end
  end

  def health_label
    STATUS_LABELS.fetch(health_status)
  end

  def health_tone
    STATUS_TONES.fetch(health_status)
  end

  def health_message
    case health_status
    when :not_archiving
      "Archive retained data is off. Old telemetry follows retention windows and can be deleted without writing archive files."
    when :archive_not_required
      "Archive retained data is on, but retention cleanup can still delete rows without a successful archive first."
    when :needs_attention
      "The latest archive failure is newer than the latest successful archive."
    when :archive_gap
      "At least one retained scope has candidates that are older than the latest completed archive."
    when :awaiting_cleanup
      "The retention worker has not recorded a cleanup for this project yet."
    else
      "Retention cleanup must write a successful archive before matching rows can be deleted."
    end
  end

  def coverage_rows
    @coverage_rows ||= begin
      rows = [
        build_coverage_row(
          key: :hot_events,
          label: "Activity events",
          description: "Logs, metrics, transactions, and check-ins.",
          retention_days: policy.hot_retention_days,
          archive_scope: "hot_events"
        ),
        build_coverage_row(
          key: :trace_spans,
          label: "Trace spans",
          description: "Request waterfalls and child span detail.",
          retention_days: policy.trace_retention_days,
          archive_scope: "trace_spans"
        )
      ]

      if policy.error_retention_days.present?
        rows << build_coverage_row(
          key: :error_events,
          label: "Error events",
          description: "Error event rows retained for closed groups.",
          retention_days: policy.error_retention_days,
          archive_scope: "error_events",
          candidates_key: :closed_error_groups,
          deleted_key: nil,
          note: "Archived before closed groups are pruned."
        )
      end

      rows << build_coverage_row(
        key: :closed_error_groups,
        label: "Closed error groups",
        description: "Resolved, ignored, or archived error groups.",
        retention_days: policy.error_retention_days,
        archive_scope: (policy.error_retention_days.present? ? "error_events" : nil),
        candidates_key: :closed_error_groups,
        note: policy.error_retention_days.present? ? "Pruning is protected by the error event archive." : "Open and closed error groups are preserved."
      )

      rows
    end
  end

  private

  def build_coverage_row(key:, label:, description:, retention_days:, archive_scope:, candidates_key: key, deleted_key: key, note: nil)
    last_archive = archive_scope.present? ? latest_completed_archive(archive_scope) : nil
    last_failure = archive_scope.present? ? latest_failed_archive(archive_scope) : nil
    cutoff_at = retention_days.present? ? cleanup_cutoff_for(retention_days) : nil
    archived_through_at = archive_scope.present? ? archived_through_for(archive_scope) : nil
    candidate_count = result_count(:candidates, candidates_key)
    status = coverage_status(
      retention_days: retention_days,
      archive_scope: archive_scope,
      archived_through_at: archived_through_at,
      cutoff_at: cutoff_at,
      candidate_count: candidate_count,
      last_archive: last_archive,
      last_failure: last_failure
    )

    CoverageRow.new(
      key: key,
      label: label,
      description: description,
      retention_days: retention_days,
      cutoff_at: cutoff_at,
      archive_scope: archive_scope,
      archived_through_at: archived_through_at,
      last_archive: last_archive,
      last_failure: last_failure,
      last_rows: last_archive&.rows,
      last_deleted: deleted_key.present? ? result_count(:deleted, deleted_key) : nil,
      candidate_count: candidate_count,
      status: status,
      note: note
    )
  end

  def cleanup_cutoff_for(retention_days)
    (last_cleanup_at || now) - retention_days.days
  end

  def coverage_status(retention_days:, archive_scope:, archived_through_at:, cutoff_at:, candidate_count:, last_archive:, last_failure:)
    return :kept_forever if retention_days.blank?
    return :not_archiving if archive_scope.present? && !policy.archive_enabled?
    return :archive_not_required if archive_scope.present? && !policy.archive_before_delete?
    return :failed if newer_failure?(last_failure, last_archive)
    return :awaiting_cleanup if last_cleanup_at.blank?
    return :no_candidates if candidate_count == 0
    return :no_archive_yet if archive_scope.present? && archived_through_at.blank?
    return :archive_gap if archive_scope.present? && cutoff_at.present? && archived_through_at < cutoff_at

    archive_scope.present? ? :covered : :no_candidates
  end

  def newer_failure?(failure, success)
    failure.present? && (success.blank? || failure.created_at >= success.created_at)
  end

  def latest_completed_archive(scope)
    project.telemetry_archives.completed.where(scope: scope.to_s).recent_first.first
  end

  def latest_failed_archive(scope)
    project.telemetry_archives.failed.where(scope: scope.to_s).recent_first.first
  end

  def archived_through_for(scope)
    project.telemetry_archives.completed.where(scope: scope.to_s).maximum(:before_at)
  end

  def result_count(group, key)
    value = @last_retention_result.dig(group, key)
    value.to_i if value.present? || value == 0
  end
end

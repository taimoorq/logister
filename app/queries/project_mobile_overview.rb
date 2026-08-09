# frozen_string_literal: true

class ProjectMobileOverview
  IdentityCoverage = Data.define(:state, :observed, :total)
  Result = Data.define(
    :open_issues,
    :newly_received_issues,
    :total_issues,
    :activity_received,
    :latest_diagnostic_received_at,
    :latest_activity_received_at,
    :current_release,
    :release_count,
    :installation_coverage,
    :session_coverage,
    :source_counts,
    :capability_snapshot
  )

  attr_reader :project, :now

  def initialize(project, now: Time.current)
    raise ArgumentError, "Mobile overview is available only for Android and iOS projects" unless project.integration_android? || project.integration_ios?

    @project = project
    @now = now
  end

  def call
    release_index = ProjectMobileReleaseIndex.new(project).call
    occurrence_facts = aggregate_occurrence_facts
    activity = project.ingest_events.where.not(event_type: IngestEvent.event_types.fetch("error"))

    Result.new(
      open_issues: project.error_groups.unresolved.count,
      newly_received_issues: occurrence_scope.where(created_at: (now - 24.hours)..).distinct.count(:error_group_id),
      total_issues: project.error_groups.count,
      activity_received: activity.where(created_at: (now - 24.hours)..).count,
      latest_diagnostic_received_at: occurrence_facts.fetch("latest_received_at"),
      latest_activity_received_at: activity.maximum(:created_at),
      current_release: release_index.releases.first,
      release_count: release_index.total_builds,
      installation_coverage: coverage(occurrence_facts.fetch("installation_observations").to_i, occurrence_facts.fetch("occurrence_count").to_i),
      session_coverage: coverage(occurrence_facts.fetch("session_observations").to_i, occurrence_facts.fetch("occurrence_count").to_i),
      source_counts: source_counts.freeze,
      capability_snapshot: ProjectCapabilitySnapshot.for(project)
    ).freeze
  end

  private

  def occurrence_scope
    @occurrence_scope ||= ErrorOccurrence.joins(:error_group).where(error_groups: { project_id: project.id })
  end

  def aggregate_occurrence_facts
    occurrence_scope.pick(
      Arel.sql("COUNT(*) AS occurrence_count"),
      Arel.sql("COUNT(installation_hash) AS installation_observations"),
      Arel.sql("COUNT(session_hash) AS session_observations"),
      Arel.sql("MAX(error_occurrences.created_at) AS latest_received_at")
    ).then do |values|
      values ||= [ 0, 0, 0, nil ]
      {
        "occurrence_count" => values[0],
        "installation_observations" => values[1],
        "session_observations" => values[2],
        "latest_received_at" => values[3]
      }
    end
  end

  def source_counts
    occurrence_scope
      .group(Arel.sql("COALESCE(NULLIF(error_occurrences.dimensions ->> 'evidence_source', ''), NULLIF(error_occurrences.dimensions ->> 'diagnostic_source', ''), 'unlabelled')"))
      .count
  end

  def coverage(observed, total)
    state = if total.zero?
      :not_collected
    elsif observed.zero?
      :not_collected
    elsif observed == total
      :complete
    else
      :partial
    end
    IdentityCoverage.new(state:, observed:, total:).freeze
  end
end

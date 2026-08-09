# frozen_string_literal: true

class ProjectMobileReleaseIndex
  Release = Data.define(
    :app_version,
    :build_number,
    :channel,
    :platform,
    :issue_count,
    :occurrence_count,
    :affected_installations,
    :identity_coverage,
    :first_received_at,
    :last_received_at,
    :last_evidence_at,
    :time_precisions,
    :sources,
    :artifact_state
  ) do
    def label
      version = app_version.presence || "Version unknown"
      build_number.present? ? "#{version} (#{build_number})" : version
    end

    def channel_label
      channel.presence || "Channel unknown"
    end
  end

  Result = Data.define(:releases, :has_more, :total_builds)
  DEFAULT_LIMIT = 50
  MAX_LIMIT = 100

  attr_reader :project, :limit, :offset

  def initialize(project, limit: DEFAULT_LIMIT, offset: 0)
    raise ArgumentError, "Mobile releases are available only for Android and iOS projects" unless project.integration_android? || project.integration_ios?

    @project = project
    @limit = Integer(limit).clamp(1, MAX_LIMIT)
    @offset = [ Integer(offset), 0 ].max
  end

  def call
    rows = grouped_scope.limit(limit + 1).offset(offset).to_a
    releases = rows.first(limit).map { |row| release_from(row) }.freeze
    Result.new(releases:, has_more: rows.size > limit, total_builds: total_builds).freeze
  end

  private

  def occurrence_scope
    ErrorOccurrence.joins(:error_group).where(error_groups: { project_id: project.id })
  end

  def grouped_scope
    occurrence_scope
      .select(
        "COALESCE(error_occurrences.dimensions ->> 'app_version', '') AS app_version",
        "COALESCE(error_occurrences.dimensions ->> 'build_number', '') AS build_number",
        "COALESCE(NULLIF(error_occurrences.dimensions ->> 'track', ''), NULLIF(error_occurrences.dimensions ->> 'distribution_channel', ''), '') AS channel",
        "COALESCE(NULLIF(error_occurrences.dimensions ->> 'apple_platform', ''), NULLIF(error_occurrences.dimensions ->> 'os_name', ''), '') AS platform",
        "COUNT(DISTINCT error_occurrences.error_group_id) AS issue_count",
        "COUNT(*) AS occurrence_count",
        "COUNT(DISTINCT error_occurrences.installation_hash) AS affected_installations",
        "COUNT(error_occurrences.installation_hash) AS installation_observations",
        "MIN(error_occurrences.created_at) AS first_received_at",
        "MAX(error_occurrences.created_at) AS last_received_at",
        "MAX(error_occurrences.occurred_at) AS last_evidence_at",
        "ARRAY_REMOVE(ARRAY_AGG(DISTINCT error_occurrences.dimensions ->> 'time_precision'), NULL) AS time_precisions",
        "ARRAY_REMOVE(ARRAY_AGG(DISTINCT COALESCE(error_occurrences.dimensions ->> 'evidence_source', error_occurrences.dimensions ->> 'diagnostic_source')), NULL) AS sources",
        "ARRAY_REMOVE(ARRAY_AGG(DISTINCT COALESCE(error_occurrences.dimensions ->> 'mapping_status', error_occurrences.dimensions ->> 'symbolication_status')), NULL) AS artifact_states"
      )
      .group(
        "COALESCE(error_occurrences.dimensions ->> 'app_version', '')",
        "COALESCE(error_occurrences.dimensions ->> 'build_number', '')",
        "COALESCE(NULLIF(error_occurrences.dimensions ->> 'track', ''), NULLIF(error_occurrences.dimensions ->> 'distribution_channel', ''), '')",
        "COALESCE(NULLIF(error_occurrences.dimensions ->> 'apple_platform', ''), NULLIF(error_occurrences.dimensions ->> 'os_name', ''), '')"
      )
      .order(Arel.sql("MAX(error_occurrences.created_at) DESC, COALESCE(error_occurrences.dimensions ->> 'build_number', '') DESC"))
  end

  def total_builds
    occurrence_scope
      .pick(Arel.sql("COUNT(DISTINCT CONCAT_WS('|', COALESCE(dimensions ->> 'app_version', ''), COALESCE(dimensions ->> 'build_number', ''), COALESCE(dimensions ->> 'track', dimensions ->> 'distribution_channel', '')))"))
      .to_i
  end

  def release_from(row)
    occurrence_count = row.occurrence_count.to_i
    installation_observations = row.installation_observations.to_i
    Release.new(
      app_version: row.app_version.presence,
      build_number: row.build_number.presence,
      channel: row.channel.presence,
      platform: row.platform.presence,
      issue_count: row.issue_count.to_i,
      occurrence_count:,
      affected_installations: row.affected_installations.to_i,
      identity_coverage: identity_coverage(installation_observations, occurrence_count),
      first_received_at: row.first_received_at,
      last_received_at: row.last_received_at,
      last_evidence_at: row.last_evidence_at,
      time_precisions: Array(row.time_precisions).compact_blank.sort.freeze,
      sources: Array(row.sources).compact_blank.sort.freeze,
      artifact_state: artifact_state(Array(row.artifact_states).compact_blank)
    ).freeze
  end

  def identity_coverage(observed, total)
    return :not_collected if observed.zero?
    return :complete if observed == total

    :partial
  end

  def artifact_state(states)
    return :not_observed if states.empty?

    if project.integration_android?
      return :complete if states.all? { |state| state == "mapping_matched" }
      return :missing if states.any? { |state| state == "missing" }
    else
      relevant = states - %w[symbols_included not_applicable]
      return :not_applicable if relevant.empty?
      return :complete if relevant.all? { |state| state == "artifact_matched" }
      return :missing if relevant.any? { |state| state == "missing" }
    end

    :partial
  end
end

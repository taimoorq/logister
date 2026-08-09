# frozen_string_literal: true

class ProjectMobileDistributionSnapshot
  Result = Data.define(
    :provider,
    :label,
    :status,
    :fetched_at,
    :report_start,
    :report_end,
    :release_count,
    :metric_row_count,
    :population_note,
    :last_error
  )

  attr_reader :project

  def initialize(project)
    raise ArgumentError, "Mobile distribution snapshots apply only to Android and iOS projects" unless project.integration_android? || project.integration_ios?

    @project = project
  end

  def call
    provider = project.integration_android? ? :google_play : :app_store_connect
    setting = project.integration_settings.find_by(provider: ProjectIntegrationSetting::PROVIDERS.fetch(provider))
    reporting = setting&.metadata&.fetch("reporting", {}) || {}
    status = ProjectCapabilitySnapshot.for(project).status(:distribution_store)

    Result.new(
      provider:,
      label: project.integration_android? ? "Google Play" : "App Store Connect",
      status:,
      fetched_at: parse_time(reporting["fetched_at"]) || setting&.last_imported_at,
      report_start: parse_date(reporting.dig("window", "start")),
      report_end: parse_date(reporting.dig("window", "end")),
      release_count: release_count(reporting),
      metric_row_count: metric_row_count(reporting),
      population_note: population_note(reporting),
      last_error: bounded_error(setting)
    ).freeze
  end

  private

  def release_count(reporting)
    Array(reporting.dig("release_filter_options", "tracks")).sum do |track|
      Array(track["servingReleases"]).size
    end
  end

  def metric_row_count(reporting)
    if project.integration_android?
      Array(reporting.dig("crash_rates", "rows")).size + Array(reporting.dig("anr_rates", "rows")).size
    else
      count_metric_rows(reporting["metrics"])
    end
  end

  def count_metric_rows(value)
    case value
    when Array then value.sum { |entry| entry.is_a?(Hash) ? 1 + count_metric_rows(entry) : 1 }
    when Hash then value.values.sum { |entry| count_metric_rows(entry) }
    else 0
    end
  end

  def population_note(reporting)
    reporting["freshness_note"].presence ||
      if project.integration_android?
        "Google Play aggregates cover only the selected reporting window, tracks, and eligible Play population."
      else
        "Apple aggregates require sufficient opted-in usage and can arrive after the app release."
      end
  end

  def bounded_error(setting)
    setting&.metadata&.dig("last_error", "message").to_s.first(500).presence
  end

  def parse_time(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  def parse_date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end
end

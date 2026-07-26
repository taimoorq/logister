# frozen_string_literal: true

class ProjectSetupStatus
  attr_reader :project

  def initialize(project)
    @project = project
  end

  def call
    context = latest_context
    app = context.fetch("app", {})
    sdk = context.fetch("sdk", {})

    {
      active_api_key: project.api_keys.active.exists?,
      has_events: latest_event.present?,
      source_repository: project.source_repositories.enabled.exists?,
      deployments: project.deployments.exists?,
      mobile_token: project.mobile_ingest_tokens.where(revoked_at: nil).where("expires_at > ?", Time.current).exists?,
      release_metadata: occurrence_scope.where("COALESCE(error_occurrences.release, '') <> ''").exists?,
      app_build_metadata: app["identifier"].present? && app["version_name"].present? && app["version_code"].present?,
      sessions: occurrence_scope.where.not(session_hash: nil).exists? || sdk["session_tracking"] == true,
      installations: occurrence_scope.where.not(installation_hash: nil).exists?,
      breadcrumbs: Array(context["breadcrumbs"]).any?,
      automatic_capture: sdk["automatic_crash_capture"] == true,
      metric_kit: dimension_present?("diagnostic_source", "metrickit"),
      android_mapping: project.respond_to?(:android_mapping_files) && project.android_mapping_files.exists?,
      google_play: integration_configured?(:google_play),
      apple_symbols: project.respond_to?(:apple_symbol_artifacts) && project.apple_symbol_artifacts.where(status: "ready").exists?,
      app_store: integration_configured?(:app_store_connect)
    }
  end

  private

  def latest_event
    @latest_event ||= project.ingest_events.order(occurred_at: :desc).select(:id, :context, :occurred_at).first
  end

  def latest_context
    MobileTelemetryNormalizer.normalize(latest_event&.context)
  end

  def occurrence_scope
    @occurrence_scope ||= ErrorOccurrence.joins(:error_group).where(error_groups: { project_id: project.id })
  end

  def dimension_present?(key, value)
    return false unless ErrorOccurrence.column_names.include?("dimensions")

    occurrence_scope.where("error_occurrences.dimensions ->> ? = ?", key, value).exists?
  end

  def integration_configured?(provider)
    project.integration_settings.find_by(provider: ProjectIntegrationSetting::PROVIDERS.fetch(provider))&.configured? || false
  end
end

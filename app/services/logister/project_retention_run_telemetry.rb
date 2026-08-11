# frozen_string_literal: true

module Logister
  class ProjectRetentionRunTelemetry
    EVENT_NAME = "project_retention_run.logister"
    ALLOWED_DETAILS = %i[action reason error_class wait_seconds].freeze

    def self.emit(event:, run:, at: Time.current, **details)
      payload = {
        event: event.to_s,
        at: at.utc.iso8601(6),
        run_id: run.id,
        project_id: run.project_id,
        status: run.status,
        phase: run.phase,
        current_scope: run.current_scope,
        attempts: run.attempts,
        fence_version: run.fence_version,
        objects_total: run.objects_total,
        objects_completed: run.objects_completed,
        rows_total: run.rows_total,
        rows_completed: run.rows_completed
      }.merge(details.slice(*ALLOWED_DETAILS).compact)

      ActiveSupport::Notifications.instrument(EVENT_NAME, payload)
      Rails.logger.info("project_retention_run #{payload.to_json}")
      payload
    rescue StandardError => error
      Rails.logger.warn("Project retention telemetry failed: #{error.class} #{error.message}")
      nil
    end
  end
end

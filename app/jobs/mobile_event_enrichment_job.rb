# frozen_string_literal: true

class MobileEventEnrichmentJob < ApplicationJob
  queue_as :symbols

  discard_on ActiveRecord::RecordNotFound
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(project_id, event_uuid, event_occurred_at)
    project = Project.find(project_id)
    return unless project.integration_android? || project.integration_ios?

    occurred_at = Time.zone.parse(event_occurred_at.to_s)
    event = project.ingest_events.where(uuid: event_uuid, occurred_at: occurred_at).first
    return unless event

    if project.integration_android?
      MobileEventEnrichments::Android.call(project: project, event: event)
    else
      MobileEventEnrichments::Apple.call(project: project, event: event)
    end
    refresh_occurrence_dimensions(event)
  end

  private

  def refresh_occurrence_dimensions(event)
    occurrence = event.error_occurrence
    return unless occurrence

    dimensions = ErrorOccurrenceDimensions.new(event).attributes[:dimensions]
    occurrence.update_columns(dimensions:, updated_at: Time.current) if dimensions
  end
end

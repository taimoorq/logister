# frozen_string_literal: true

class MobileArtifactCoverageRefreshJob < ApplicationJob
  queue_as :maintenance
  BATCH_SIZE = 250
  PLATFORMS = %w[android ios].freeze

  def perform(project_id, platform, after_id = 0)
    platform = platform.to_s
    return unless platform.in?(PLATFORMS)

    project = Project.find_by(id: project_id)
    return unless project && project.public_send("integration_#{platform}?")

    occurrences = ErrorOccurrence.joins(:error_group)
      .where(error_groups: { project_id: project.id })
      .where("error_occurrences.id > ?", after_id.to_i)
      .order(:id)
      .limit(BATCH_SIZE)
      .to_a
    return if occurrences.empty?

    events = IngestEvent.partition_reference_index(
      occurrences,
      id_key: :ingest_event_id,
      occurred_at_key: :ingest_event_occurred_at
    )
    occurrences.each do |occurrence|
      event = events[occurrence.ingest_event_id]
      next unless event

      dimensions = ErrorOccurrenceDimensions.new(event).attributes[:dimensions]
      occurrence.update_columns(dimensions: dimensions, updated_at: Time.current) if dimensions
    end

    if occurrences.size == BATCH_SIZE
      self.class.perform_later(project.id, platform, occurrences.last.id)
    end
  end
end

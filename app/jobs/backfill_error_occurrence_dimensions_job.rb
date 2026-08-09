# frozen_string_literal: true

class BackfillErrorOccurrenceDimensionsJob < ApplicationJob
  queue_as :maintenance

  BATCH_SIZE = 200

  def perform(project_id: nil)
    project_ids = if project_id.present?
      Project.where(id: project_id, integration_kind: %i[android ios]).select(:id)
    else
      Project.where(integration_kind: %i[android ios]).select(:id)
    end
    scope = ErrorOccurrence
      .joins(:error_group)
      .where(error_groups: { project_id: project_ids })
      .where(
        "COALESCE(error_occurrences.dimensions ->> 'materialization_version', '0') <> ?",
        ErrorOccurrenceDimensions::MATERIALIZATION_VERSION.to_s
      )

    scope.find_in_batches(batch_size: BATCH_SIZE) do |occurrences|
      events_by_id = IngestEvent.partition_reference_index(
        occurrences,
        id_key: :ingest_event_id,
        occurred_at_key: :ingest_event_occurred_at
      )

      occurrences.each do |occurrence|
        event = events_by_id[occurrence.ingest_event_id]
        occurrence.materialize_dimensions!(event) if event
      end
    end
  end
end

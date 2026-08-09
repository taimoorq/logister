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
    refresh_android_enrichments(project, events.values.compact) if platform == "android"
    schedule_apple_enrichments(project, events.values.compact) if platform == "ios"
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

  private

  def refresh_android_enrichments(project, events)
    presenters = events.index_with { |event| ProjectEvents::AndroidEventPresenter.new(event) }
    mapping_keys = presenters.values.filter_map do |presenter|
      app = presenter.app_details
      next if app[:package_name].blank? || app[:version_code].blank?

      [ app[:package_name], app[:version_code].to_s ]
    end.uniq
    mappings = mapping_keys.reduce(project.android_mapping_files.none) do |relation, (package_name, version_code)|
      relation.or(project.android_mapping_files.where(package_name: package_name, version_code: version_code))
    end.index_by { |mapping| [ mapping.package_name, mapping.version_code.to_s ] }

    presenters.each do |event, presenter|
      app = presenter.app_details
      MobileEventEnrichments::Android.call(
        project: project,
        event: event,
        presenter: presenter,
        mapping_file: mappings[[ app[:package_name], app[:version_code].to_s ]]
      )
    end
  end

  def schedule_apple_enrichments(project, events)
    events.each do |event|
      MobileEventEnrichmentJob.perform_later(project.id, event.uuid, event.occurred_at.utc.iso8601(6))
    end
  end
end

# frozen_string_literal: true

class ProjectNotificationEvidence
  FACET_KEYS = {
    "evidence_source" => "evidence_source",
    "diagnostic_kind" => "diagnostic_kind",
    "build_number" => "build_number",
    "distribution_channel" => "distribution_channel",
    "time_precision" => "time_precision"
  }.freeze

  class << self
    def enrich(project:, error_group:, metadata:)
      values = metadata.to_h.stringify_keys
      return values unless mobile_project?(project) && error_group

      occurrence = occurrence_for(error_group, values)
      dimensions = occurrence&.dimensions.to_h
      facets = FACET_KEYS.each_with_object({}) do |(metadata_key, dimension_key), result|
        result[metadata_key] = dimensions[dimension_key] if dimensions[dimension_key].present?
      end
      facets["artifact_state"] = dimensions["mapping_status"].presence || dimensions["symbolication_status"].presence
      facets.compact.merge(values)
    end

    def event_for(error_group:, metadata:)
      occurrence_for(error_group, metadata.to_h.stringify_keys)&.ingest_event_record
    end

    private

    def occurrence_for(error_group, metadata)
      occurrence = occurrence_for_event(error_group, metadata)
      occurrence || error_group.error_occurrences.order(created_at: :desc, id: :desc).first
    end

    def occurrence_for_event(error_group, metadata)
      event_id = Integer(metadata["event_id"], exception: false)
      return unless event_id

      candidates = error_group.error_occurrences.where(ingest_event_id: event_id).order(created_at: :desc, id: :desc).to_a
      return candidates.first if candidates.one?

      occurred_at = parse_time(metadata["occurred_at"])
      return candidates.first unless occurred_at

      candidates.min_by { |candidate| (candidate.ingest_event_occurred_at.to_f - occurred_at.to_f).abs }
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError, TypeError
      nil
    end

    def mobile_project?(project)
      project.integration_android? || project.integration_ios?
    end
  end
end

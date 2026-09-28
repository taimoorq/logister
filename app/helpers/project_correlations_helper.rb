# frozen_string_literal: true

module ProjectCorrelationsHelper
  def correlation_record_path(item)
    if item[:type] == "span"
      project_request_path(item[:project_uuid], item[:uuid], occurred_at: item[:occurred_at], environment: item[:environment])
    else
      # ClickHouse stores millisecond timestamps; do not use a rounded value as
      # an exact PostgreSQL partition predicate. The project-scoped UUID is stable.
      project_event_path(item[:project_uuid], item[:uuid])
    end
  end

  def correlation_evidence_label(item)
    { "parent_span" => "Parent/child span", "shared_trace" => "Shared trace", "shared_request_id" => "Shared request ID" }[item[:evidence]]
  end

  def correlation_outcome(item)
    return "Error observed" if item[:type] == "error"
    return "HTTP #{item[:http_status_code]}" if item[:http_status_code]

    { "ok" => "Completed", "error" => "Failure recorded" }.fetch(item[:status], "Outcome not captured")
  end

  def correlation_request_summary(result, project)
    return "Evidence is incomplete" if result[:partial]
    peers = result[:items].reject { |item| item[:project_uuid] == project.uuid }
    return "Related error observed" if peers.any? { |item| item[:type] == "error" }
    return "Related request failure recorded" if peers.any? { |item| item[:status] == "error" || item[:http_status_code].to_i >= 400 }
    return "Related request completed" if peers.any? { |item| item[:status] == "ok" }
    return "Related activity observed" if peers.any?

    "No matching connected-project evidence"
  end
end

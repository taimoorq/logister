module ProjectEventDetailData
  extend ActiveSupport::Concern

  private

  def build_project_event_detail(project, event, group: nil)
    resolved_group = group || event.error_group
    occurrences = if resolved_group
      resolved_group.error_occurrences.includes(:ingest_event).recent_first.limit(50)
    else
      []
    end

    {
      event: event,
      group: resolved_group,
      occurrences: occurrences,
      related_logs: IngestEvent.related_logs(project: project, event: event, window: 5.minutes, limit: 50)
    }
  end
end

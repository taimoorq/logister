module ProjectEventDetailData
  extend ActiveSupport::Concern

  private

  def build_project_event_detail(project, event, group: nil)
    resolved_group = group || event.error_group
    occurrences = if resolved_group
      partitioned_occurrences(resolved_group.error_occurrences.recent_first.limit(50).to_a)
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

  def partitioned_occurrences(occurrences)
    events_by_id = IngestEvent.for_partition_references(
      occurrences,
      id_key: :ingest_event_id,
      occurred_at_key: :ingest_event_occurred_at
    ).index_by(&:id)

    occurrences.each do |occurrence|
      occurrence.ingest_event_record = events_by_id[occurrence.ingest_event_id]
    end
  end
end

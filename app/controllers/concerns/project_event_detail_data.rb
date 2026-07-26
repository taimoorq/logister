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
      related_logs: IngestEvent.related_logs(project: project, event: event, window: 5.minutes, limit: 50),
      impact_summary: resolved_group && ProjectExperience.for(project).supports?(:mobile) ? ErrorGroupImpactSummary.for_group(resolved_group, since: detail_impact_since) : nil
    }
  end

  def partitioned_occurrences(occurrences)
    events_by_id = IngestEvent.partition_reference_index(
      occurrences,
      id_key: :ingest_event_id,
      occurred_at_key: :ingest_event_occurred_at
    )

    occurrences.each do |occurrence|
      occurrence.ingest_event_record = events_by_id[occurrence.ingest_event_id]
    end
  end

  def detail_impact_since
    range = params[:time_range].to_s
    return nil if range == "all"

    ({ "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days, "90d" => 90.days }[range] || 30.days).ago
  end
end

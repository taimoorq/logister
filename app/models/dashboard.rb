# Aggregates dashboard summary data for a user's projects (counts, recent event ids, error event ids).
# Used by DashboardController; caching is done in the controller.
class Dashboard
  def self.summary_for(project_ids)
    return empty_summary if project_ids.blank?

    {
      projects_count: Project.where(id: project_ids).count,
      api_keys_count: ApiKey.where(project_id: project_ids).count,
      events_last_24h: IngestEvent.where(project_id: project_ids).where("occurred_at >= ?", 24.hours.ago).count,
      recent_event_ids: IngestEvent.where(project_id: project_ids).order(occurred_at: :desc).limit(20).pluck(:id),
      error_event_ids: IngestEvent.where(project_id: project_ids, event_type: :error)
                                  .where("occurred_at >= ?", 7.days.ago)
                                  .order(occurred_at: :desc)
                                  .limit(320)
                                  .pluck(:id)
    }
  end

  def self.cache_version(project_ids)
    return [] if project_ids.blank?

    [
      IngestEvent.where(project_id: project_ids).maximum(:updated_at)&.utc&.to_i || 0,
      ApiKey.where(project_id: project_ids).maximum(:updated_at)&.utc&.to_i || 0
    ]
  end

  def self.empty_summary
    {
      projects_count: 0,
      api_keys_count: 0,
      events_last_24h: 0,
      recent_event_ids: [],
      error_event_ids: []
    }
  end
end

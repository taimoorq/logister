# Aggregates dashboard summary data for a user's projects (counts, recent event ids, error event ids).
# Used by DashboardController; caching is done in the controller.
class Dashboard
  def self.summary_for(project_ids)
    return empty_summary if project_ids.blank?

    events_scope = IngestEvent.where(project_id: project_ids)
    api_keys_scope = ApiKey.where(project_id: project_ids)

    {
      projects_count: project_ids.size,
      api_keys_count: relation_count(api_keys_scope),
      events_last_24h: relation_count(events_scope.where("occurred_at >= ?", 24.hours.ago)),
      recent_event_ids: events_scope.order(occurred_at: :desc).limit(20).pluck(:id),
      error_event_ids: events_scope.where(event_type: IngestEvent.event_types[:error])
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

  def self.relation_count(relation)
    relation.count(:all)
  end
  private_class_method :relation_count
end

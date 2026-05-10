# Aggregates dashboard summary data for a user's projects (counts, recent event ids, error event ids).
# Used by DashboardController; caching is done in the controller.
class Dashboard
  EVENT_TYPE_ORDER = %w[error log metric transaction check_in].freeze

  def self.summary_for(project_ids)
    return empty_summary if project_ids.blank?

    events_scope = IngestEvent.where(project_id: project_ids)
    events_last_24h_scope = events_scope.where("occurred_at >= ?", 24.hours.ago)
    error_groups_scope = ErrorGroup.where(project_id: project_ids)
    api_keys_scope = ApiKey.where(project_id: project_ids)
    monitors = CheckInMonitor.where(project_id: project_ids)
                             .select(:id, :last_status, :last_check_in_at, :expected_interval_seconds)
                             .to_a

    {
      projects_count: project_ids.size,
      api_keys_count: relation_count(api_keys_scope),
      events_last_24h: relation_count(events_last_24h_scope),
      active_project_ids_last_24h: events_last_24h_scope.distinct.pluck(:project_id),
      events_by_type_last_24h: event_type_counts(events_last_24h_scope),
      open_error_groups_count: relation_count(error_groups_scope.unresolved),
      new_error_groups_last_24h: relation_count(error_groups_scope.where("first_seen_at >= ?", 24.hours.ago)),
      projects_with_open_errors_count: error_groups_scope.unresolved.distinct.count(:project_id),
      monitors_count: monitors.size,
      monitor_status_counts: monitor_status_counts(monitors),
      recent_event_ids: events_scope.order(occurred_at: :desc).limit(20).pluck(:id),
      recent_error_group_ids: error_groups_scope.unresolved.order(last_seen_at: :desc).limit(6).pluck(:id),
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
      ApiKey.where(project_id: project_ids).maximum(:updated_at)&.utc&.to_i || 0,
      ErrorGroup.where(project_id: project_ids).maximum(:updated_at)&.utc&.to_i || 0,
      CheckInMonitor.where(project_id: project_ids).maximum(:updated_at)&.utc&.to_i || 0
    ]
  end

  def self.empty_summary
    {
      projects_count: 0,
      api_keys_count: 0,
      events_last_24h: 0,
      active_project_ids_last_24h: [],
      events_by_type_last_24h: EVENT_TYPE_ORDER.index_with { 0 },
      open_error_groups_count: 0,
      new_error_groups_last_24h: 0,
      projects_with_open_errors_count: 0,
      monitors_count: 0,
      monitor_status_counts: { ok: 0, missed: 0, error: 0 },
      recent_event_ids: [],
      recent_error_group_ids: [],
      error_event_ids: []
    }
  end

  def self.relation_count(relation)
    relation.count(:all)
  end
  private_class_method :relation_count

  def self.event_type_counts(relation)
    counts = relation.group(:event_type).count

    EVENT_TYPE_ORDER.index_with do |event_type|
      counts[event_type].to_i + counts[IngestEvent.event_types[event_type]].to_i
    end
  end
  private_class_method :event_type_counts

  def self.monitor_status_counts(monitors)
    monitors.each_with_object({ ok: 0, missed: 0, error: 0 }) do |monitor, counts|
      status = monitor.status.to_sym
      counts[status] = counts.fetch(status, 0) + 1
    end
  end
  private_class_method :monitor_status_counts
end

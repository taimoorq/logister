# Aggregates dashboard summary and explorer data for a user's projects.
# Used by DashboardController; caching is done in the controller.
class Dashboard
  EVENT_TYPE_ORDER = %w[error log metric transaction check_in].freeze
  EXPLORER_ENVIRONMENT_LIMIT = 8
  EXPLORER_WINDOW = 7.days

  def self.summary_for(project_ids)
    return empty_summary if project_ids.blank?

    events_scope = IngestEvent.where(project_id: project_ids)
    events_last_24h_scope = events_scope.where("occurred_at >= ?", 24.hours.ago)
    error_groups_scope = ErrorGroup.where(project_id: project_ids)
    api_keys_scope = ApiKey.where(project_id: project_ids)
    events_by_type_last_24h = event_type_counts(events_last_24h_scope)
    open_error_group_counts = error_groups_scope.unresolved.group(:project_id).count
    activity_event_counts = events_last_24h_scope.where.not(event_type: IngestEvent.event_types[:error]).group(:project_id).count
    latest_event_at_by_project = events_scope.group(:project_id).maximum(:occurred_at)
    monitors = CheckInMonitor.where(project_id: project_ids)
                             .select(:id, :last_status, :last_check_in_at, :expected_interval_seconds)
                             .to_a

    {
      projects_count: project_ids.size,
      api_keys_count: relation_count(api_keys_scope),
      events_last_24h: events_by_type_last_24h.values.sum,
      active_project_ids_last_24h: events_last_24h_scope.distinct.pluck(:project_id),
      events_by_type_last_24h: events_by_type_last_24h,
      open_error_groups_count: open_error_group_counts.values.sum,
      new_error_groups_last_24h: relation_count(error_groups_scope.where("first_seen_at >= ?", 24.hours.ago)),
      projects_with_open_errors_count: open_error_group_counts.size,
      monitors_count: monitors.size,
      monitor_status_counts: monitor_status_counts(monitors),
      recent_event_ids: events_scope.order(occurred_at: :desc).limit(20).pluck(:id),
      recent_error_group_ids: error_groups_scope.unresolved.order(last_seen_at: :desc).limit(6).pluck(:id),
      project_stats: project_stats(project_ids,
                                   open_error_group_counts: open_error_group_counts,
                                   activity_event_counts: activity_event_counts,
                                   latest_event_at_by_project: latest_event_at_by_project)
    }
  end

  def self.explorer_for(project_ids, since: EXPLORER_WINDOW.ago, event_type: nil, project_id: nil, environment: nil)
    return empty_explorer if project_ids.blank?

    project_ids = filtered_project_ids(project_ids, project_id)
    return empty_explorer if project_ids.blank?

    events_scope = explorer_scope(project_ids, since:, event_type:, environment:)
    open_error_group_counts = ErrorGroup.where(project_id: project_ids).unresolved.group(:project_id).count

    {
      window_started_at: since.utc.iso8601,
      window_days: ((Time.current - since) / 1.day).ceil,
      totals: explorer_totals(events_scope),
      timeline: explorer_timeline(events_scope),
      event_types: explorer_event_type_counts(events_scope),
      projects: explorer_project_counts(events_scope, open_error_group_counts),
      environments: explorer_environment_counts(events_scope)
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

  def self.empty_explorer
    {
      window_started_at: EXPLORER_WINDOW.ago.utc.iso8601,
      window_days: EXPLORER_WINDOW.in_days.to_i,
      totals: { events: 0, active_projects: 0, environments: 0 },
      timeline: [],
      event_types: EVENT_TYPE_ORDER.index_with { 0 },
      projects: [],
      environments: []
    }
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
      project_stats: {}
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

  def self.filtered_project_ids(project_ids, project_id)
    project_ids = Array(project_ids).map(&:to_i)
    requested_project_id = project_id.to_i if project_id.present?

    return project_ids if requested_project_id.blank?

    project_ids.include?(requested_project_id) ? [ requested_project_id ] : []
  end
  private_class_method :filtered_project_ids

  def self.explorer_scope(project_ids, since:, event_type:, environment:)
    relation = IngestEvent.where(project_id: project_ids).where("occurred_at >= ?", since)
    relation = relation.where(event_type: event_type) if event_type.present? && IngestEvent.event_types.key?(event_type)
    relation = relation.where("#{environment_expression} = ?", environment) if environment.present?
    relation
  end
  private_class_method :explorer_scope

  def self.explorer_totals(relation)
    {
      events: relation_count(relation),
      active_projects: relation.distinct.count(:project_id),
      environments: relation.group(Arel.sql(environment_expression)).count.size
    }
  end
  private_class_method :explorer_totals

  def self.explorer_timeline(relation)
    day_bucket = Arel.sql("DATE(occurred_at)")
    relation.group(day_bucket, :event_type).count.map do |dimensions, count|
      day, event_type = dimensions

      {
        event_type: event_type_name(event_type),
        day: day.to_date.iso8601,
        count: count.to_i
      }
    end.sort_by { |row| [ row[:day], row[:event_type] ] }
  end
  private_class_method :explorer_timeline

  def self.explorer_event_type_counts(relation)
    counts = relation.group(:event_type).count

    EVENT_TYPE_ORDER.index_with do |event_type|
      counts[event_type].to_i + counts[IngestEvent.event_types[event_type]].to_i
    end
  end
  private_class_method :explorer_event_type_counts

  def self.explorer_project_counts(relation, open_error_group_counts)
    relation.group(:project_id).count.map do |project_id, count|
      {
        project_id: project_id.to_i,
        count: count.to_i,
        open_errors: open_error_group_counts[project_id].to_i
      }
    end.sort_by { |row| [ -row[:count], -row[:open_errors], row[:project_id] ] }
  end
  private_class_method :explorer_project_counts

  def self.explorer_environment_counts(relation)
    relation.group(Arel.sql(environment_expression)).count.map do |environment, count|
      { name: environment.to_s.presence || "unknown", count: count.to_i }
    end.sort_by { |row| [ -row[:count], row[:name] ] }.first(EXPLORER_ENVIRONMENT_LIMIT)
  end
  private_class_method :explorer_environment_counts

  def self.environment_expression
    "COALESCE(NULLIF(context->>'environment', ''), 'unknown')"
  end
  private_class_method :environment_expression

  def self.event_type_name(value)
    return value.to_s if IngestEvent.event_types.key?(value.to_s)

    IngestEvent.event_types.key(value.to_i) || value.to_s
  end
  private_class_method :event_type_name

  def self.monitor_status_counts(monitors)
    monitors.each_with_object({ ok: 0, missed: 0, error: 0 }) do |monitor, counts|
      status = monitor.status.to_sym
      counts[status] = counts.fetch(status, 0) + 1
    end
  end
  private_class_method :monitor_status_counts

  def self.project_stats(project_ids, open_error_group_counts:, activity_event_counts:, latest_event_at_by_project:)
    project_ids.index_with do |project_id|
      {
        open_groups: open_error_group_counts[project_id].to_i,
        activity_events: activity_event_counts[project_id].to_i,
        latest_event_at: latest_event_at_by_project[project_id]
      }
    end
  end
  private_class_method :project_stats
end

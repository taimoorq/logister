# Aggregates dashboard summary and explorer data for a user's projects.
# Used by DashboardController; caching is done in the controller.
class Dashboard
  EVENT_TYPE_ORDER = %w[error log metric transaction check_in].freeze
  EXPLORER_ENVIRONMENT_LIMIT = 8
  EXPLORER_EVENT_LIMIT = 200
  EXPLORER_WINDOW_DAYS = 7
  EXPLORER_WINDOW = EXPLORER_WINDOW_DAYS.days

  def self.summary_for(project_ids,
                       viewer: nil,
                       include_assignments: true,
                       include_context_events: true,
                       include_project_signals: true,
                       include_project_stats: true,
                       recent_error_group_limit: 6,
                       recent_context_event_limit: 12)
    return empty_summary if project_ids.blank?

    events_scope = IngestEvent.where(project_id: project_ids)
    events_since = 24.hours.ago
    events_until = Time.current
    events_last_24h_scope = events_scope.where("occurred_at >= ?", events_since)
    error_groups_scope = ErrorGroup.where(project_id: project_ids)
    api_keys_scope = ApiKey.where(project_id: project_ids)
    open_error_group_counts = error_groups_scope.unresolved.group(:project_id).count
    recent_error_group_ids = error_groups_scope.unresolved.order(last_seen_at: :desc).limit(recent_error_group_limit).pluck(:id)
    event_rollup = if include_project_signals || include_project_stats
      dashboard_event_rollup(project_ids, events_last_24h_scope, since: events_since, to: events_until)
    end
    events_by_type_last_24h = include_project_signals ? event_rollup.fetch(:event_type_counts) : EVENT_TYPE_ORDER.index_with { 0 }
    active_project_ids_last_24h = include_project_signals ? event_rollup.fetch(:active_project_ids) : []
    monitors = if include_project_signals
      CheckInMonitor.monitoring
                    .where(project_id: project_ids)
                    .select(:id, :last_status, :last_check_in_at, :expected_interval_seconds, :monitoring_paused_at)
                    .to_a
    else
      []
    end

    assigned_error_groups_scope = include_assignments && viewer.present? ? error_groups_scope.unresolved.assigned_to(viewer) : ErrorGroup.none
    assigned_error_group_counts = include_assignments && viewer.present? ? assigned_error_groups_scope.group(:project_id).count : {}
    unassigned_error_group_counts = include_assignments ? error_groups_scope.unresolved.unassigned.group(:project_id).count : {}
    recent_context_event_refs = if include_context_events
      events_last_24h_scope
        .where.not(event_type: IngestEvent.event_types[:error])
        .order(occurred_at: :desc)
        .limit(recent_context_event_limit)
        .pluck(:id, :occurred_at)
        .map { |id, occurred_at| { id: id, occurred_at: occurred_at } }
    else
      []
    end

    project_stats = if include_project_stats
      project_stats(project_ids,
                    open_error_group_counts: open_error_group_counts,
                    activity_event_counts: event_rollup.fetch(:activity_event_counts),
                    latest_event_at_by_project: event_rollup.fetch(:latest_event_at_by_project))
    else
      {}
    end

    {
      projects_count: project_ids.size,
      api_keys_count: include_project_signals ? relation_count(api_keys_scope) : 0,
      events_last_24h: events_by_type_last_24h.values.sum,
      active_project_ids_last_24h: active_project_ids_last_24h,
      events_by_type_last_24h: events_by_type_last_24h,
      open_error_groups_count: open_error_group_counts.values.sum,
      assigned_error_groups_count: assigned_error_group_counts.values.sum,
      assigned_error_group_ids: assigned_error_groups_scope.order(last_seen_at: :desc).limit(5).pluck(:id),
      projects_with_assigned_errors_count: assigned_error_group_counts.size,
      unassigned_error_groups_count: unassigned_error_group_counts.values.sum,
      projects_with_unassigned_errors_count: unassigned_error_group_counts.size,
      new_error_groups_last_24h: relation_count(error_groups_scope.where("first_seen_at >= ?", 24.hours.ago)),
      projects_with_open_errors_count: open_error_group_counts.size,
      monitors_count: monitors.size,
      monitor_status_counts: monitor_status_counts(monitors),
      recent_context_event_refs: recent_context_event_refs,
      recent_context_event_ids: recent_context_event_refs.pluck(:id),
      recent_error_group_ids: recent_error_group_ids,
      project_stats: project_stats,
      analytics: event_rollup&.fetch(:analytics, nil)
    }
  end

  def self.explorer_for(project_ids, since: nil, event_type: nil, project_id: nil, environment: nil, occurred_on: nil)
    return empty_explorer if project_ids.blank?

    since ||= explorer_window_start
    project_ids = filtered_project_ids(project_ids, project_id)
    return empty_explorer if project_ids.blank?

    open_error_group_counts = ErrorGroup.where(project_id: project_ids).unresolved.group(:project_id).count
    days = explorer_days_for(since, occurred_on)
    ended_at = Time.current
    events_scope = explorer_scope(project_ids, since:, event_type:, environment:, occurred_on:)
    read = Logister::ClickhouseReadRouter.call(
      project_ids:,
      signals: event_type.present? ? [ event_type ] : EVENT_TYPE_ORDER,
      from: since,
      to: ended_at,
      clickhouse: ->(client) {
        Logister::ClickhouseExplorer.call(
          project_ids:,
          since:,
          to: ended_at,
          event_type:,
          environment:,
          occurred_on: explorer_filter_date(occurred_on),
          environment_limit: EXPLORER_ENVIRONMENT_LIMIT,
          client:
        )
      },
      postgres: -> { postgres_explorer_payload(events_scope, open_error_group_counts) }
    )
    explorer_payload = read.payload

    if read.clickhouse?
      explorer_payload[:projects].each do |row|
        row[:open_errors] = open_error_group_counts[row[:project_id]].to_i
      end
    end

    {
      window_started_at: since.utc.iso8601,
      window_days: days.size,
      days: days,
      **explorer_payload,
      analytics: read.diagnostics
    }
  end

  def self.explorer_events_for(project_ids, since: nil, event_type: nil, project_id: nil, environment: nil, occurred_on: nil, limit: EXPLORER_EVENT_LIMIT)
    return IngestEvent.none if project_ids.blank?

    since ||= explorer_window_start
    project_ids = filtered_project_ids(project_ids, project_id)
    return IngestEvent.none if project_ids.blank?

    explorer_scope(project_ids, since:, event_type:, environment:, occurred_on:)
      .includes(:project, :error_group)
      .order(occurred_at: :desc, id: :desc)
      .limit(limit)
  end

  def self.empty_explorer
    since = explorer_window_start
    days = explorer_days(since)

    {
      window_started_at: since.utc.iso8601,
      window_days: days.size,
      days: days,
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
      assigned_error_groups_count: 0,
      assigned_error_group_ids: [],
      projects_with_assigned_errors_count: 0,
      unassigned_error_groups_count: 0,
      projects_with_unassigned_errors_count: 0,
      new_error_groups_last_24h: 0,
      projects_with_open_errors_count: 0,
      monitors_count: 0,
      monitor_status_counts: { ok: 0, missed: 0, error: 0 },
      recent_context_event_refs: [],
      recent_context_event_ids: [],
      recent_error_group_ids: [],
      project_stats: {}
    }
  end

  def self.relation_count(relation)
    relation.count(:all)
  end
  private_class_method :relation_count

  def self.explorer_window_start
    (EXPLORER_WINDOW_DAYS - 1).days.ago.beginning_of_day
  end
  private_class_method :explorer_window_start

  def self.explorer_days(since)
    start_date = since.to_date
    end_date = Time.current.to_date

    (start_date..end_date).map(&:iso8601)
  end
  private_class_method :explorer_days

  def self.explorer_days_for(since, occurred_on)
    day = explorer_filter_date(occurred_on)

    day.present? ? [ day.iso8601 ] : explorer_days(since)
  end
  private_class_method :explorer_days_for

  def self.event_type_counts(relation)
    counts = relation.group(:event_type).count

    EVENT_TYPE_ORDER.index_with do |event_type|
      counts[event_type].to_i + counts[IngestEvent.event_types[event_type]].to_i
    end
  end
  private_class_method :event_type_counts

  def self.dashboard_event_rollup(project_ids, relation, since:, to:)
    postgres = -> {
      {
        event_type_counts: event_type_counts(relation),
        active_project_ids: relation.distinct.pluck(:project_id),
        activity_event_counts: relation.where.not(event_type: IngestEvent.event_types[:error]).group(:project_id).count,
        latest_event_at_by_project: relation.group(:project_id).maximum(:occurred_at)
      }
    }
    read = Logister::ClickhouseReadRouter.call(
      project_ids:,
      signals: EVENT_TYPE_ORDER,
      from: since,
      to:,
      clickhouse: ->(client) { Logister::ClickhouseEventRollup.call(project_ids:, since:, to:, client:) },
      postgres:
    )
    read.payload.merge(analytics: read.diagnostics)
  end
  private_class_method :dashboard_event_rollup

  def self.postgres_explorer_payload(relation, open_error_group_counts)
    {
      totals: explorer_totals(relation),
      timeline: explorer_timeline(relation),
      event_types: explorer_event_type_counts(relation),
      projects: explorer_project_counts(relation, open_error_group_counts),
      environments: explorer_environment_counts(relation)
    }
  end
  private_class_method :postgres_explorer_payload

  def self.filtered_project_ids(project_ids, project_id)
    project_ids = Array(project_ids).map(&:to_i)
    requested_project_id = project_id.to_i if project_id.present?

    return project_ids if requested_project_id.blank?

    project_ids.include?(requested_project_id) ? [ requested_project_id ] : []
  end
  private_class_method :filtered_project_ids

  def self.explorer_scope(project_ids, since:, event_type:, environment:, occurred_on:)
    relation = IngestEvent.where(project_id: project_ids).where("occurred_at >= ?", since)
    relation = relation.where(event_type: event_type) if event_type.present? && IngestEvent.event_types.key?(event_type)
    if (day = explorer_filter_date(occurred_on))
      relation = relation.where(occurred_at: day.all_day)
    end
    if environment.present?
      relation = relation.where(
        "COALESCE(NULLIF(context->>'environment', ''), 'unknown') = ?",
        environment
      )
    end
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

  def self.explorer_filter_date(value)
    return value if value.is_a?(Date)
    return value.to_date if value.respond_to?(:to_date)
    return if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
  private_class_method :explorer_filter_date

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

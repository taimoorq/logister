class ProjectsController < ApplicationController
  PROJECT_FILTERS = %w[active archived all].freeze
  PROJECT_DASHBOARD_CACHE_TTL = 30.seconds
  PROJECT_OVERVIEW_CACHE_TTL = 30.seconds
  PROJECT_STATS_CACHE_TTL = 45.seconds
  LEGACY_INBOX_PARAMS = %w[filter q assignee group_uuid event_uuid tab frame_scope frame].freeze

  include ProjectInboxData
  include ProjectEventDetailData
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project, only: [ :show, :inbox ]
  before_action :set_owned_project, only: [ :edit, :update, :archive, :restore, :destroy ]

  def index
    accessible = current_user.accessible_projects
    @project_filter = params[:filter].presence_in(PROJECT_FILTERS) || "active"
    @project_filter_counts = project_filter_counts(accessible)
    @projects = filtered_projects(accessible, @project_filter).order(created_at: :desc).to_a
    project_ids    = @projects.map(&:id)
    @project_stats = project_ids.any? ? cached_project_stats(project_ids) : {}
    @projects_overview = projects_overview(@projects, @project_stats)
  end

  def show
    if legacy_inbox_request?
      render_project_inbox
      return
    end

    @counts = inbox_counts(@project, viewer: current_user)
    @project_overview = project_overview(@project)
    dashboard_metrics = project_dashboard_metrics(@project)
    @event_type_counts_last_24h = dashboard_metrics[:event_type_counts_last_24h]
    @insights_payload = ProjectInsights.shell_payload(
      @project,
      endpoint: insights_data_project_path(@project),
      window: ProjectInsights::DEFAULT_WINDOW,
      storage_key: "logister.project-overview-insights.#{@project.uuid}"
    )
    @events_last_24h = @event_type_counts_last_24h.values.sum
    @activity_events_last_24h = @event_type_counts_last_24h.except("error").values.sum
    @recent_error_groups = @project.error_groups
                                   .unresolved
                                   .includes(:assignee)
                                   .recent_first
                                   .limit(5)
    @db_stats = dashboard_metrics[:db_stats]
    @transaction_stats = dashboard_metrics[:transaction_stats]
    @request_span_count_last_24h = @project.trace_spans
                                            .where(kind: TraceSpan::ROOT_KINDS, started_at: 24.hours.ago..)
                                            .count
  end

  def inbox
    render_project_inbox
  end

  def new
    @project = current_user.projects.new
  end

  def create
    @project = current_user.projects.new(project_create_params)
    if @project.save
      redirect_to settings_project_path(@project, anchor: "integration-guide"),
                  notice: "Project created. Follow the #{@project.integration_label} setup guide to start ingesting events."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @project.update(project_update_params)
      redirect_to settings_project_path(@project), notice: "Project updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def archive
    @project.archive!
    redirect_to projects_path, notice: "Project #{@project.name} was archived. Its data is still available from archived projects."
  end

  def restore
    @project.restore!
    redirect_to project_path(@project), notice: "Project #{@project.name} is active again."
  end

  def destroy
    project_name = @project.name

    if @project.destroy
      redirect_to projects_path, notice: "Project #{project_name} was deleted."
    else
      redirect_to project_path(@project), alert: @project.errors.full_messages.to_sentence.presence || "Project could not be deleted."
    end
  end

  private

  def render_project_inbox
    @filter = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    @query  = params[:q].to_s.strip
    @assignee_filter = normalize_inbox_assignee_filter(@project, params[:assignee], viewer: current_user)
    @assignable_users = @project.assignable_users.to_a
    @tab    = params[:tab].presence_in(%w[context stacktrace occurrences related_logs]) || "stacktrace"
    @groups = inbox_groups(@project, filter: @filter, query: @query, assignee: @assignee_filter, viewer: current_user)
    @latest_events = inbox_latest_events(@groups)
    @has_activity_events = @groups.empty? && project_has_activity_events?(@project)

    # Turbo Frame request targeting the inbox list — return only the table partial.
    if turbo_frame_request? && request.headers["Turbo-Frame"] == "project_inbox"
      @selected_uuid = params[:group_uuid]
      return render partial: "projects/inbox_table", locals: {
        project:       @project,
        groups:        @groups,
        latest_events: @latest_events,
        group_trends:  inbox_group_trends(@project, @groups),
        has_activity_events: @has_activity_events,
        selected_uuid: @selected_uuid,
        filter:        @filter,
        query:         @query,
        assignee:      @assignee_filter
      }
    end

    # Full page load — build everything the workbench needs for the inbox.
    @counts  = inbox_counts(@project, assignee: @assignee_filter, viewer: current_user)
    @group_trends = inbox_group_trends(@project, @groups)
    @project_overview = project_overview(@project)
    @selected_group = if params[:group_uuid].present?
      @project.error_groups.find_by(uuid: params[:group_uuid])
    else
      @groups.first
    end

    @selected_event = if params[:event_uuid].present?
      @project.ingest_events.find_by(uuid: params[:event_uuid])
    end

    # Safety: if the requested event does not belong to the selected group, ignore it.
    if @selected_event && @selected_group && @selected_event.error_group_id != @selected_group.id
      @selected_event = nil
    end

    detail_event = @selected_event || @selected_group&.latest_event
    if detail_event.present?
      detail_data = build_project_event_detail(@project, detail_event, group: @selected_group)
      @detail_event = detail_data[:event]
      @detail_group = detail_data[:group]
      @detail_occurrences = detail_data[:occurrences]
      @detail_related_logs = detail_data[:related_logs]
    end

    render :inbox unless performed?
  end

  def legacy_inbox_request?
    (request.query_parameters.keys & LEGACY_INBOX_PARAMS).any?
  end

  def project_create_params
    params.require(:project).permit(:name, :description, :integration_kind)
  end

  def project_update_params
    params.require(:project).permit(:name, :description)
  end

  def filtered_projects(scope, filter)
    case filter
    when "archived" then scope.archived
    when "all" then scope
    else scope.active
    end
  end

  def project_filter_counts(scope)
    {
      active: scope.active.count,
      archived: scope.archived.count,
      all: scope.count
    }
  end

  def cached_project_stats(project_ids)
    cache_key = [ "projects_stats", current_user.id, project_ids, cache_time_bucket(PROJECT_STATS_CACHE_TTL) ]
    safe_cache_fetch(cache_key, expires_in: PROJECT_STATS_CACHE_TTL) { Project.stats_for(project_ids) }
  end

  def projects_overview(projects, project_stats)
    stats = projects.filter_map { |project| project_stats[project.id] }
    active_projects_count = stats.count { |project| project[:activity_events].to_i.positive? }

    {
      projects_count: projects.size,
      open_groups_count: stats.sum { |project| project[:open_groups].to_i },
      activity_events_count: stats.sum { |project| project[:activity_events].to_i },
      active_projects_count: active_projects_count,
      quiet_projects_count: [ projects.size - active_projects_count, 0 ].max
    }
  end

  def project_overview(project)
    safe_cache_fetch(
      [ "project", project.id, "overview", cache_time_bucket(PROJECT_OVERVIEW_CACHE_TTL) ],
      expires_in: PROJECT_OVERVIEW_CACHE_TTL
    ) do
      events = project.ingest_events
      events_last_24h = events.where("occurred_at >= ?", 24.hours.ago)
      monitors = project.check_in_monitors
                        .select(:id, :last_status, :last_check_in_at, :expected_interval_seconds)
                        .to_a
      monitor_status_counts = monitors.each_with_object({ ok: 0, missed: 0, error: 0 }) do |monitor, counts|
        status = monitor.status.to_sym
        counts[status] = counts.fetch(status, 0) + 1
      end

      {
        events_last_24h: events_last_24h.count,
        activity_events_last_24h: events_last_24h.where.not(event_type: IngestEvent.event_types[:error]).count,
        latest_event_at: Project.latest_event_at_by_project([ project.id ])[project.id],
        monitors_count: monitors.size,
        monitor_status_counts: monitor_status_counts,
        unhealthy_monitors_count: monitor_status_counts.fetch(:missed, 0) + monitor_status_counts.fetch(:error, 0)
      }
    end
  end

  def project_event_type_counts(project, since:)
    counts = project.ingest_events.where("occurred_at >= ?", since).group(:event_type).count

    Dashboard::EVENT_TYPE_ORDER.index_with do |event_type|
      counts[event_type].to_i + counts[IngestEvent.event_types[event_type]].to_i
    end
  end

  def project_dashboard_metrics(project)
    safe_cache_fetch(
      [ "project", project.id, "dashboard_metrics", cache_time_bucket(PROJECT_DASHBOARD_CACHE_TTL) ],
      expires_in: PROJECT_DASHBOARD_CACHE_TTL
    ) do
      since = 24.hours.ago
      db_query_events = project.ingest_events.recent_db_queries(since).select(:id, :context).to_a

      {
        event_type_counts_last_24h: project_event_type_counts(project, since: since),
        db_stats: IngestEvent.db_stats_from_events(db_query_events),
        transaction_stats: IngestEvent.transaction_stats(project, since: since)
      }
    end
  end
end

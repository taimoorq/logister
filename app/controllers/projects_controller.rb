class ProjectsController < ApplicationController
  include ProjectInboxData
  include ProjectEventDetailData
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project, only: [ :show ]
  before_action :set_owned_project, only: [ :edit, :update, :destroy ]

  def index
    @projects      = current_user.accessible_projects.order(created_at: :desc).to_a
    project_ids    = @projects.map(&:id)
    @project_stats = project_ids.any? ? cached_project_stats(project_ids) : {}
    @projects_overview = projects_overview(@projects, @project_stats)
  end

  def show
    @filter = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    @query  = params[:q].to_s.strip
    @tab    = params[:tab].presence_in(%w[context stacktrace occurrences related_logs]) || "stacktrace"
    @groups = inbox_groups(@project, filter: @filter, query: @query)

    # Turbo Frame request targeting the inbox list — return only the table partial.
    if turbo_frame_request? && request.headers["Turbo-Frame"] == "project_inbox"
      @selected_uuid = params[:group_uuid]
      return render partial: "projects/inbox_table", locals: {
        project:       @project,
        groups:        @groups,
        group_trends:  inbox_group_trends(@project, @groups),
        selected_uuid: @selected_uuid,
        filter:        @filter,
        query:         @query
      }
    end

    # Full page load — build everything the workbench needs for the inbox.
    @counts  = inbox_counts(@project)
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
    return unless detail_event.present?

    detail_data = build_project_event_detail(@project, detail_event, group: @selected_group)
    @detail_event = detail_data[:event]
    @detail_group = detail_data[:group]
    @detail_occurrences = detail_data[:occurrences]
    @detail_related_logs = detail_data[:related_logs]
  end

  def new
    @project = current_user.projects.new
  end

  def create
    @project = current_user.projects.new(project_params)
    if @project.save
      redirect_to project_path(@project), notice: "Project created. Add an API key to start ingesting events."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_to settings_project_path(@project), notice: "Project updated."
    else
      render :edit, status: :unprocessable_content
    end
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

  def project_params
    params.require(:project).permit(:name, :description, :integration_kind)
  end

  def cached_project_stats(project_ids)
    cache_key = [ "projects_stats", current_user.id, project_ids, Project.stats_cache_version(project_ids) ]
    safe_cache_fetch(cache_key, expires_in: 45.seconds) { Project.stats_for(project_ids) }
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
    safe_cache_fetch([ "project", project.id, "overview", project_overview_cache_version(project) ], expires_in: 30.seconds) do
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
        latest_event_at: events.maximum(:occurred_at),
        monitors_count: monitors.size,
        monitor_status_counts: monitor_status_counts,
        unhealthy_monitors_count: monitor_status_counts.fetch(:missed, 0) + monitor_status_counts.fetch(:error, 0)
      }
    end
  end

  def project_overview_cache_version(project)
    [
      project.ingest_events.maximum(:updated_at)&.utc&.to_i || 0,
      project.check_in_monitors.maximum(:updated_at)&.utc&.to_i || 0
    ]
  end
end

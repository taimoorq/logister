class ProjectsController < ApplicationController
  include ProjectInboxData
  include ProjectEventDetailData
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project, only: [ :show ]
  before_action :set_owned_project, only: [ :edit, :update, :destroy ]

  def index
    @projects      = current_user.accessible_projects.order(created_at: :desc)
    project_ids    = @projects.pluck(:id)
    @project_stats = project_ids.any? ? cached_project_stats(project_ids) : {}
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
        selected_uuid: @selected_uuid,
        filter:        @filter,
        query:         @query
      }
    end

    # Full page load — build everything the workbench needs for the inbox.
    @counts  = inbox_counts(@project)
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
    params.require(:project).permit(:name, :slug, :description, :integration_kind)
  end

  def cached_project_stats(project_ids)
    cache_key = [ "projects_stats", current_user.id, Project.stats_cache_version(project_ids) ]
    safe_cache_fetch(cache_key, expires_in: 45.seconds) { Project.stats_for(project_ids) }
  end
end

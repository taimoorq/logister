class ProjectsController < ApplicationController
  include ProjectInboxData

  before_action :authenticate_user!
  before_action :set_project, only: :show
  before_action :set_owned_project, only: :destroy

  def index
    @projects      = current_user.accessible_projects.order(created_at: :desc)
    project_ids    = @projects.pluck(:id)
    @project_stats = project_ids.any? ? cached_project_stats(project_ids) : {}
  end

  def show
    @filter = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    @query  = params[:q].to_s.strip
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

    # Full page load — build everything the workbench needs.
    @counts  = inbox_counts(@project)
    @owner   = @project.user
    @project_memberships = @project.project_memberships.includes(:user).order(created_at: :asc)
    @api_keys = @project.api_keys.order(created_at: :desc)

    @selected_group = if params[:group_uuid].present?
      @project.error_groups.find_by(uuid: params[:group_uuid])
    else
      @groups.first
    end

    @db_query_events  = @project.ingest_events.recent_db_queries(24.hours.ago).to_a
    @db_stats        = IngestEvent.db_stats_from_events(@db_query_events)
    @slow_db_queries = @db_query_events.sort_by { |e| -IngestEvent.duration_ms(e) }.first(20)
  end

  def new
    @project = current_user.projects.new
  end

  def create
    @project = current_user.projects.new(project_params)
    if @project.save
      redirect_to project_path(@project), notice: "Project created. Add an API key to start ingesting events."
    else
      render :new, status: :unprocessable_entity
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

  def set_project
    @project = current_user.accessible_projects.find_by!(uuid: params[:uuid])
  end

  def set_owned_project
    @project = current_user.projects.find_by!(uuid: params[:uuid])
  end

  def project_params
    params.require(:project).permit(:name, :slug, :description)
  end

  def cached_project_stats(project_ids)
    cache_key = [ "projects_stats", current_user.id, Project.stats_cache_version(project_ids) ]
    safe_cache_fetch(cache_key, expires_in: 45.seconds) { Project.stats_for(project_ids) }
  end
end

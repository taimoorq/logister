class ProjectsController < ApplicationController
  include ProjectInboxData

  before_action :authenticate_user!
  before_action :set_project, only: :show

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

    @db_query_events = @project.ingest_events.metric
                               .where(message: "db.query")
                               .where("occurred_at >= ?", 24.hours.ago)
                               .order(occurred_at: :desc)
                               .limit(300)
                               .to_a
    @db_stats        = build_db_stats(@db_query_events)
    @slow_db_queries = @db_query_events.sort_by { |e| -db_duration_ms(e) }.first(20)
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

  private

  def set_project
    @project = current_user.accessible_projects.find_by!(uuid: params[:uuid])
  end

  def project_params
    params.require(:project).permit(:name, :slug, :description)
  end

  def build_project_stats(project_ids)
    stats = Hash.new { |h, k| h[k] = { total_events: 0, open_groups: 0, trend: Array.new(7, 0) } }

    ErrorGroup.where(project_id: project_ids).unresolved.group(:project_id).count
              .each { |pid, c| stats[pid][:open_groups] = c }

    IngestEvent.where(project_id: project_ids).group(:project_id).count
               .each { |pid, c| stats[pid][:total_events] = c }

    trend_dates = 7.times.map { |i| Date.current - (6 - i) }
    ErrorOccurrence
      .joins(:error_group)
      .where(error_groups: { project_id: project_ids })
      .where("error_occurrences.occurred_at >= ?", 7.days.ago)
      .group("error_groups.project_id", "DATE(error_occurrences.occurred_at)")
      .count
      .each do |(pid, date), count|
        idx = trend_dates.index(date.to_date)
        stats[pid][:trend][idx] = count if idx
      end

    stats
  end

  def cached_project_stats(project_ids)
    cache_key = [ "projects_stats", current_user.id, projects_stats_cache_version(project_ids) ]
    safe_cache_fetch(cache_key, expires_in: 45.seconds) { build_project_stats(project_ids) }
  end

  def projects_stats_cache_version(project_ids)
    latest_group = ErrorGroup.where(project_id: project_ids).maximum(:updated_at)&.utc&.to_i || 0
    latest_event = IngestEvent.where(project_id: project_ids).maximum(:updated_at)&.utc&.to_i || 0
    latest_occurrence = ErrorOccurrence.joins(:error_group)
                                       .where(error_groups: { project_id: project_ids })
                                       .maximum(:updated_at)&.utc&.to_i || 0
    [ latest_group, latest_event, latest_occurrence ]
  end

  def build_db_stats(events)
    durations = events.map { |e| db_duration_ms(e) }.select(&:positive?)
    return { count: 0, avg_ms: 0.0, p95_ms: 0.0 } if durations.empty?

    sorted    = durations.sort
    p95_index = [ (sorted.length * 0.95).ceil - 1, 0 ].max
    { count: durations.length, avg_ms: (durations.sum / durations.length).round(2), p95_ms: sorted[p95_index].round(2) }
  end

  def db_duration_ms(event)
    value = event.context.is_a?(Hash) ? (event.context["duration_ms"] || event.context[:duration_ms]) : nil
    value.to_f
  end
end

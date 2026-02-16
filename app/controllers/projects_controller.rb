class ProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project, only: :show

  def index
    @projects = current_user.accessible_projects.order(created_at: :desc)
  end

  def show
    @owner = @project.user
    @project_memberships = @project.project_memberships.includes(:user).order(created_at: :asc)
    @api_keys = @project.api_keys.order(created_at: :desc)
    @events = @project.ingest_events.order(occurred_at: :desc).limit(50)
    @db_query_events = @project.ingest_events.metric
                               .where(message: "db.query")
                               .where("occurred_at >= ?", 24.hours.ago)
                               .order(occurred_at: :desc)
                               .limit(300)
    @db_stats = build_db_stats(@db_query_events)
    @slow_db_queries = @db_query_events.sort_by { |event| -db_duration_ms(event) }.first(20)
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

  def build_db_stats(events)
    durations = events.map { |event| db_duration_ms(event) }.select { |ms| ms.positive? }
    return { count: 0, avg_ms: 0.0, p95_ms: 0.0 } if durations.empty?

    sorted = durations.sort
    p95_index = ([ (sorted.length * 0.95).ceil - 1, 0 ].max)

    {
      count: durations.length,
      avg_ms: (durations.sum / durations.length).round(2),
      p95_ms: sorted[p95_index].round(2)
    }
  end

  def db_duration_ms(event)
    value = event.context.is_a?(Hash) ? (event.context["duration_ms"] || event.context[:duration_ms]) : nil
    value.to_f
  end
end

class ProjectsController < ApplicationController
  PROJECT_FILTERS = %w[active archived all].freeze
  PROJECT_DASHBOARD_CACHE_TTL = 30.seconds
  PROJECT_STATS_CACHE_TTL = 45.seconds
  LEGACY_INBOX_PARAMS = %w[filter q assignee group_uuid event_uuid tab frame_scope frame].freeze

  include ProjectInboxData
  include ProjectEventDetailData
  include ProjectScope
  include ProjectsControllerData

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
    dashboard_metrics = project_dashboard_metrics(@project)
    @insights_payload = ProjectInsights.shell_payload(
      @project,
      endpoint: insights_data_project_path(@project),
      window: ProjectInsights::DEFAULT_WINDOW,
      storage_key: "logister.project-overview-insights.#{@project.uuid}"
    )
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
    @monitor_this_installation = false
    build_default_retention_policy
    load_self_monitoring_creation_context
  end

  def create
    @project = current_user.projects.new(project_create_params)
    @monitor_this_installation = ActiveModel::Type::Boolean.new.cast(params.dig(:project, :monitor_this_installation))

    if invalid_self_monitoring_request?
      build_default_retention_policy
      load_self_monitoring_creation_context
      return render :new, status: :unprocessable_content
    end

    if retention_policy_attributes_missing?
      build_default_retention_policy
      @project.errors.add(:base, "Choose a data retention policy before creating the project.")
      @project.retention_policy.errors.add(:base, "Choose a data retention policy before creating the project.")
      load_self_monitoring_creation_context
      return render :new, status: :unprocessable_content
    end

    if @project.save
      connection = connect_self_monitoring_project if @monitor_this_installation
      redirect_to setup_project_path(@project),
                  **project_created_flash(connection)
    else
      build_default_retention_policy
      load_self_monitoring_creation_context
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @project.update(project_update_params)
      redirect_to settings_project_path(@project, section: "general"), notice: "Project updated."
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

  def invalid_self_monitoring_request?
    return false unless @monitor_this_installation

    unless admin_user?
      @project.errors.add(:base, "Application admin access is required to connect installation self-monitoring.")
      return true
    end

    return false if @project.integration_ruby?

    @project.errors.add(:integration_kind, "must be Ruby when monitoring this Logister installation")
    true
  end

  def connect_self_monitoring_project
    Logister::SelfMonitoringConnector.call(project: @project, actor: current_user)
  rescue StandardError => error
    Rails.logger.error("self_monitoring_project_connection_failed project_id=#{@project.id} error=#{error.class}: #{error.message}")
    error
  end

  def project_created_flash(connection)
    notice = "Project created. Create a token and send one event to verify setup."
    return { notice: notice } unless @monitor_this_installation

    if connection.respond_to?(:status) && connection.status.connected?
      {
        notice: "Project created and connected for local self-monitoring. Restart worker processes so every process uses the new credentials."
      }
    elsif connection.respond_to?(:status)
      {
        notice: "Project created and linked for local self-monitoring.",
        alert: "Update the effective observability environment settings before restarting. #{connection.status.issues.to_sentence}"
      }
    else
      {
        notice: notice,
        alert: "The project was created, but Logister could not connect it for self-monitoring. Open Admin → Installation → Observability to retry."
      }
    end
  end

  def load_self_monitoring_creation_context
    @current_self_monitoring_project = Installation.current_if_available&.self_monitoring_project if admin_user?
  end
end

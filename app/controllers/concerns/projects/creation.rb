# frozen_string_literal: true

module Projects::Creation
  extend ActiveSupport::Concern

  def new
    @project = current_user.projects.new
    @monitor_this_installation = false
    build_default_retention_policy
    load_self_monitoring_creation_context
  end

  def create
    @project = current_user.projects.new(project_create_params)
    @monitor_this_installation = ActiveModel::Type::Boolean.new.cast(params.dig(:project, :monitor_this_installation))

    return render_invalid_project if invalid_self_monitoring_request?
    return render_missing_retention_policy if retention_policy_attributes_missing?

    if @project.save
      connection = connect_self_monitoring_project if @monitor_this_installation
      redirect_to setup_project_path(@project), **project_created_flash(connection)
    else
      render_invalid_project
    end
  end

  private

  def render_invalid_project
    build_default_retention_policy
    load_self_monitoring_creation_context
    render :new, status: :unprocessable_content
  end

  def render_missing_retention_policy
    build_default_retention_policy
    message = "Choose a data retention policy before creating the project."
    @project.errors.add(:base, message)
    @project.retention_policy.errors.add(:base, message)
    load_self_monitoring_creation_context
    render :new, status: :unprocessable_content
  end

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

    return connected_project_flash if connection.respond_to?(:status) && connection.status.connected?
    return incomplete_project_connection_flash(connection) if connection.respond_to?(:status)

    {
      notice: notice,
      alert: "The project was created, but Logister could not connect it for self-monitoring. Open Admin → Installation → Observability to retry."
    }
  end

  def connected_project_flash
    {
      notice: "Project created and connected for local self-monitoring. Restart worker processes so every process uses the new credentials."
    }
  end

  def incomplete_project_connection_flash(connection)
    {
      notice: "Project created and linked for local self-monitoring.",
      alert: "Update the effective observability environment settings before restarting. #{connection.status.issues.to_sentence}"
    }
  end

  def load_self_monitoring_creation_context
    @current_self_monitoring_project = Installation.current_if_available&.self_monitoring_project if admin_user?
  end
end

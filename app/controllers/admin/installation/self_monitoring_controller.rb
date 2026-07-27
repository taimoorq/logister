# frozen_string_literal: true

class Admin::Installation::SelfMonitoringController < Admin::BaseController
  def update
    project = Project.active.find_by!(uuid: params[:project_uuid])
    result = Logister::SelfMonitoringConnector.call(project: project, actor: current_user)

    if result.status.connected?
      redirect_to admin_installation_section_path("observability"),
                  notice: "#{project.name} is connected for local self-monitoring. Restart worker processes so every process uses the new credentials."
    else
      redirect_to admin_installation_section_path("observability"),
                  alert: connection_alert(result.status)
    end
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to admin_installation_section_path("observability"), alert: error.message
  end

  private

  def connection_alert(status)
    message = "The project is linked, but self-monitoring is not connected. #{status.issues.to_sentence}"
    return message unless status.environment_override_keys.any?

    "#{message} Update #{status.environment_override_keys.to_sentence} in the environment and restart web and worker processes."
  end
end

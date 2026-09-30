# frozen_string_literal: true

module Projects::SelfMonitoringContext
  extend ActiveSupport::Concern

  private

  # Application admins can point a new Ruby project at this installation's own
  # errors; the creation forms show the current destination when there is one.
  def load_self_monitoring_creation_context
    @current_self_monitoring_project = Installation.current_if_available&.self_monitoring_project if admin_user?
  end
end

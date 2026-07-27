# frozen_string_literal: true

module Logister
  class SelfMonitoringPolicy
    MAX_FAN_OUT_DEPTH = 1

    def initialize(project:, event:, installation: Installation.current_if_available)
      @project = project
      @event = event
      @installation = installation
    end

    def local_self_monitoring?
      installation&.self_monitoring_project_id == project.id
    end

    def mirror_to_clickhouse?
      return true unless local_self_monitoring?

      within_fan_out_budget? && origin_component != "clickhouse"
    end

    def send_notifications?
      return true unless local_self_monitoring?

      within_fan_out_budget? && origin_component != "notifications"
    end

    def index_deployment?
      send_notifications?
    end

    def update_check_in_monitor?
      return true unless local_self_monitoring?

      within_fan_out_budget? && origin_component != "notifications"
    end

    private

    attr_reader :project, :event, :installation

    def within_fan_out_budget?
      InternalTelemetry.feedback_depth(event) <= MAX_FAN_OUT_DEPTH
    end

    def origin_component
      InternalTelemetry.component(event)
    end
  end
end

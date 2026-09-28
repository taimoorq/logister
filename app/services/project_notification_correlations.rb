# frozen_string_literal: true

class ProjectNotificationCorrelations
  # Resolve at mail construction, never store a peer's metadata on a delivery.
  def self.call(delivery)
    project, user, group = delivery.project, delivery.user, delivery.error_group
    return [] unless group && ProjectCorrelationPolicy.enabled?(project)
    return [] unless user.accessible_projects.exists?(id: project.id)

    event = ProjectNotificationEvidence.event_for(error_group: group, metadata: delivery.metadata) || group.latest_event_record
    return [] unless event

    result = ProjectCorrelationsQuery.call(principal: user, project:, event:)
    result[:items].reject { |item| item[:project_uuid] == project.uuid }.first(5)
      .map { |item| item.slice(:project_uuid, :project_name, :uuid, :type, :occurred_at, :environment, :operation, :evidence, :release, :status) }
  rescue ActiveRecord::RecordNotFound, ActiveRecord::QueryCanceled, ProjectCorrelationPolicy::TooManyProjects
    []
  end
end

# frozen_string_literal: true

# Decides which project pages appear in navigation from observed project state.
# Every experience uses the same rules, so a page is never hidden because of the
# project's type, only because it has nothing to show yet.
#
#   Monitors       appears once a check-in monitor exists.
#   Deploy records appears on mobile projects once a deployment is recorded.
#   Connected      appears once the project is linked and correlations are on.
#
# The page being viewed is always kept so direct visits and bookmarks resolve.
class ProjectNavigationProjection
  attr_reader :project, :capability_snapshot

  def initialize(project:, capability_snapshot:)
    @project = project
    @capability_snapshot = capability_snapshot
  end

  def resolve(pages, current_page_key: nil)
    current = current_page_key&.to_sym
    pages.select { |page| page.key == current || visible?(page) }.freeze
  end

  private

  def visible?(page)
    case page.key
    when :monitors then check_ins_configured?
    when :deployments then !mobile_project? || deployments_recorded?
    when :connections then connections_available?
    else true
    end
  end

  def mobile_project?
    project.integration_android? || project.integration_ios?
  end

  def check_ins_configured?
    capability_snapshot.status(:check_ins).state == :configured
  end

  def deployments_recorded?
    ProjectReadCache.fetch(project, :navigation_deployments_recorded, shared: true) do
      project.deployments.exists?
    end
  end

  def connections_available?
    return false unless ProjectCorrelationPolicy.enabled?(project)

    ProjectReadCache.fetch(project, :navigation_project_links, shared: true) do
      ProjectLink.touching(project).exists?
    end
  end
end

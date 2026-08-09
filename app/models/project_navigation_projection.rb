# frozen_string_literal: true

class ProjectNavigationProjection
  attr_reader :project, :capability_snapshot

  def initialize(project:, capability_snapshot:)
    @project = project
    @capability_snapshot = capability_snapshot
  end

  def resolve(pages, current_page_key: nil)
    return pages unless mobile_project?
    return pages if current_page_key&.to_sym == :monitors
    return pages if check_ins_configured?

    pages.reject { |page| page.key == :monitors }.freeze
  end

  private

  def mobile_project?
    project.integration_android? || project.integration_ios?
  end

  def check_ins_configured?
    capability_snapshot.status(:check_ins).state == :configured
  end
end

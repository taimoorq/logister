class ProjectCorrelationPolicy
  MAX_NEIGHBORS = 10
  class TooManyProjects < StandardError; end

  def self.enabled?(project)
    %w[1 true yes on].include?(ENV.fetch("LOGISTER_CROSS_PROJECT_CORRELATIONS", "false").downcase) &&
      project.cross_project_correlations_enabled? && !project.archived? && !project.purge_pending?
  end

  # The caller passes a user or a CLI token, both of which resolve current access.
  def self.projects(principal:, anchor:, environment:)
    raise ActiveRecord::RecordNotFound unless enabled?(anchor.reload)
    allowed = principal.accessible_projects.active.where(purge_requested_at: nil, cross_project_correlations_enabled: true)
    raise ActiveRecord::RecordNotFound unless allowed.exists?(id: anchor.id) && !anchor.purge_pending?
    return {} if environment.blank?

    result = { anchor.id => [ environment ] }
    ids = allowed.select(:id)
    ProjectLink.touching(anchor).where(source_project_id: ids, target_project_id: ids).order(:id).each do |link|
      environments = link.environments_for(anchor, environment)
      next if environments.empty?
      result[link.peer_id(anchor)] = (result.fetch(link.peer_id(anchor), []) + environments).uniq
    end
    raise TooManyProjects, "More than #{MAX_NEIGHBORS} connected projects; narrow the project links for this environment." if result.size > MAX_NEIGHBORS + 1
    result
  end
end

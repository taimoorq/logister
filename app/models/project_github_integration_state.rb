# frozen_string_literal: true

class ProjectGithubIntegrationState
  def initialize(project:, user:, source_repositories: nil)
    @project = project
    @user = user
    @source_repositories = source_repositories
  end

  def project_installations
    @project_installations ||= project.project_github_installations
                                      .includes(github_installation: :github_repositories)
                                      .order(created_at: :asc)
  end

  def linked_installations
    @linked_installations ||= project.github_installations
                                     .includes(:github_repositories)
                                     .order(updated_at: :desc)
  end

  def linkable_installations
    @linkable_installations ||= GithubInstallation.linkable_by(user)
                                                 .where.not(id: linked_installation_ids)
                                                 .includes(:github_repositories)
                                                 .order(updated_at: :desc)
  end

  def available_repositories
    @available_repositories ||= GithubRepository.available_for_project(project)
                                               .includes(:github_installation)
                                               .order(:full_name)
  end

  def connectable_repositories
    @connectable_repositories ||= available_repositories.reject do |repository|
      connected_repository_full_names.include?(repository.full_name.downcase)
    end
  end

  private

  attr_reader :project, :user

  def linked_installation_ids
    linked_installations.map(&:id)
  end

  def source_repositories
    @source_repositories ||= project.source_repositories
                                    .includes(:github_installation, github_repository: :github_installation)
                                    .order(:provider, :full_name)
  end

  def connected_repository_full_names
    @connected_repository_full_names ||= source_repositories.map { |source_repository| source_repository.full_name.downcase }
  end
end

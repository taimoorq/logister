# frozen_string_literal: true

class ProjectGithubIntegrationState
  def initialize(project:, user:, source_repositories: nil, app_diagnostics: nil)
    @project = project
    @user = user
    @source_repositories = source_repositories
    @app_diagnostics = app_diagnostics
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

  def app_connection_healthy?
    app_configuration_ready? && linked_installations.any?(&:available?)
  end

  def app_connection_needs_attention?
    !app_connection_healthy?
  end

  def app_access_details_open?
    app_connection_needs_attention?
  end

  def app_connection_label
    app_connection_healthy? ? "GitHub connection healthy" : "GitHub connection needs setup"
  end

  def app_connection_message
    return "GitHub App configuration is incomplete." unless app_configuration_ready?
    return "No GitHub App installation is linked to this project." if linked_installations.empty?
    return "Linked GitHub App installations are unavailable." if linked_installations.none?(&:available?)

    "Linked installations can sync repositories for this project."
  end

  def linked_installation_count
    linked_installations.size
  end

  def connected_repository_count
    source_repositories.size
  end

  def available_repository_count
    available_repositories.size
  end

  def connectable_repository_count
    connectable_repositories.size
  end

  private

  attr_reader :project, :user, :app_diagnostics

  def app_configuration_ready?
    app_diagnostics&.ready?
  end

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

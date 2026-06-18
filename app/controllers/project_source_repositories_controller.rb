class ProjectSourceRepositoriesController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_owned_project
  before_action :set_source_repository, only: [ :update, :destroy ]

  def create
    @source_repository_form = @project.source_repositories.new(source_repository_params)

    if @source_repository_form.save
      redirect_to settings_project_path(@project, section: "integrations", anchor: "source-repositories"),
                  notice: "Source repository connected."
    else
      @settings_section = "integrations"
      load_project_settings_context
      render "projects/settings", status: :unprocessable_content
    end
  end

  def update
    if @source_repository.update(source_repository_params)
      redirect_to settings_project_path(@project, section: "integrations", anchor: "source-repositories"),
                  notice: "Source repository updated."
    else
      @source_repository_form = @project.source_repositories.new(provider: ProjectSourceRepository::PROVIDERS[:github])
      @settings_section = "integrations"
      load_project_settings_context
      render "projects/settings", status: :unprocessable_content
    end
  end

  def destroy
    @source_repository.destroy
    redirect_to settings_project_path(@project, section: "integrations", anchor: "source-repositories"),
                notice: "Source repository removed."
  end

  private

  def set_source_repository
    @source_repository = @project.source_repositories.find_by!(uuid: params[:uuid])
  end

  def project_uuid_param
    params[:project_uuid] || params[:project_id] || params[:uuid]
  end

  def source_repository_params
    params.require(:project_source_repository).permit(
      :provider,
      :github_repository_id,
      :full_name,
      :default_branch,
      :runtime_root,
      :source_root,
      :enabled
    ).tap do |permitted|
      permitted[:enabled] = ActiveModel::Type::Boolean.new.cast(permitted[:enabled]) if permitted.key?(:enabled)
      normalize_github_repository_param(permitted)
    end
  end

  def normalize_github_repository_param(permitted)
    return unless permitted.key?(:github_repository_id)

    github_repository_id = permitted[:github_repository_id].presence
    if github_repository_id.blank?
      permitted[:github_repository_id] = nil
      return
    end

    github_repository = available_github_repositories.find_by(id: github_repository_id)
    permitted[:github_repository_id] = github_repository&.id
    permitted[:github_installation_id] = github_repository.github_installation_id if github_repository
  end

  def available_github_repositories
    GithubRepository.visible_to(current_user)
  end
end

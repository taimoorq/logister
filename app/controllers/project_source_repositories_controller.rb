class ProjectSourceRepositoriesController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_managed_project
  before_action :set_source_repository, only: [ :update, :destroy ]

  def create
    result = ProjectSourceRepositoryConnector.new(project: @project, attributes: source_repository_params).build
    @source_repository_form = result.source_repository

    if result.rejected?
      render_settings_with_errors
    elsif @source_repository_form.save
      redirect_to settings_project_path(@project, section: "integrations", anchor: "source-repositories"),
                  notice: "Source repository connected."
    else
      render_settings_with_errors
    end
  end

  def update
    result = ProjectSourceRepositoryConnector.new(
      project: @project,
      source_repository: @source_repository,
      attributes: source_repository_params
    ).build
    @source_repository = result.source_repository

    if result.rejected?
      render_settings_with_errors
    elsif @source_repository.save
      redirect_to settings_project_path(@project, section: "integrations", anchor: "source-repositories"),
                  notice: "Source repository updated."
    else
      render_settings_with_errors
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
    end
  end

  def render_settings_with_errors
    @source_repository_form ||= @project.source_repositories.new(provider: ProjectSourceRepository::PROVIDERS[:github])
    @settings_section = "integrations"
    load_project_settings_context
    render "projects/settings", status: :unprocessable_content
  end
end

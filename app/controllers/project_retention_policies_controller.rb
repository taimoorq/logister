class ProjectRetentionPoliciesController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_owned_project

  def update
    @retention_policy = ProjectRetentionPolicy.for(project: @project)

    if @retention_policy.update(retention_policy_params)
      redirect_to settings_project_path(@project, section: "data"), notice: "Data retention policy updated."
    else
      @settings_section = "data"
      load_project_settings_context
      render "projects/settings", status: :unprocessable_content
    end
  end

  private

  def retention_policy_params
    params.require(:project_retention_policy).permit(
      :hot_retention_days,
      :trace_retention_days,
      :error_retention_days,
      :archive_enabled,
      :archive_before_delete
    ).tap do |permitted|
      permitted[:error_retention_days] = nil if permitted.key?(:error_retention_days) && permitted[:error_retention_days].blank?
    end
  end
end

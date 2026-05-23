class ProjectRateLimitsController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  RATE_LIMIT_ATTRIBUTES = %i[
    public_api_rate_limit_requests_override
    public_api_rate_limit_period_seconds_override
    public_api_auth_failure_rate_limit_requests_override
  ].freeze

  before_action :authenticate_user!
  before_action :require_app_admin!
  before_action :set_project

  def update
    if @project.update(rate_limit_params)
      redirect_to settings_project_path(@project, anchor: "rate-limits"), notice: "Project rate limits updated."
    else
      load_project_settings_context
      render "projects/settings", status: :unprocessable_content
    end
  end

  private

  def require_app_admin!
    return if admin_user?

    redirect_to root_path, alert: "App admin access is required."
  end

  def set_project
    @project = Project.find_by!(uuid: project_uuid_param)
  end

  def rate_limit_params
    params.require(:project).permit(*RATE_LIMIT_ATTRIBUTES).tap do |permitted|
      RATE_LIMIT_ATTRIBUTES.each do |attribute|
        permitted[attribute] = nil if permitted.key?(attribute) && permitted[attribute].blank?
      end
    end
  end
end

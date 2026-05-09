module ProjectScope
  extend ActiveSupport::Concern

  private

  def set_accessible_project
    @project = current_user.accessible_projects.find_by!(uuid: project_uuid_param)
  end

  def set_owned_project
    @project = current_user.projects.find_by!(uuid: project_uuid_param)
  end

  def project_uuid_param
    params[:uuid] || params[:project_uuid] || params[:project_id]
  end
end

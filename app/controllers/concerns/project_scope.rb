module ProjectScope
  extend ActiveSupport::Concern

  private

  def set_accessible_project
    @project = current_user.accessible_projects.find_by!(uuid: params[:uuid])
  end

  def set_owned_project
    @project = current_user.projects.find_by!(uuid: params[:uuid])
  end
end

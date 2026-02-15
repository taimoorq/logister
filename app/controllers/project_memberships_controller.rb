class ProjectMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project

  def create
    user = User.find_by(email: membership_params[:email].to_s.downcase)
    return redirect_with_alert("User not found.") unless user
    return redirect_with_alert("You already own this project.") if user == @project.user

    membership = @project.project_memberships.new(user: user, role: :viewer)

    if membership.save
      redirect_to project_path(@project), notice: "Project shared with #{user.email}."
    else
      redirect_to project_path(@project), alert: membership.errors.full_messages.to_sentence
    end
  end

  def destroy
    membership_identifier = params[:uuid] || params[:id]
    membership = @project.project_memberships.find_by!(uuid: membership_identifier)
    membership.destroy!

    redirect_to project_path(@project), notice: "Access removed."
  end

  private

  def set_project
    @project = current_user.projects.find_by!(uuid: params[:project_uuid] || params[:project_id])
  end

  def membership_params
    params.require(:project_membership).permit(:email)
  end

  def redirect_with_alert(message)
    redirect_to project_path(@project), alert: message
  end
end

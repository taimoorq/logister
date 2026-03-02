class ProjectMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project

  def create
    user = User.find_by(email: membership_params[:email].to_s.downcase)

    if user.blank?
      return respond_with_membership_error("User not found.")
    end
    if user == @project.user
      return respond_with_membership_error("You already own this project.")
    end

    membership = @project.project_memberships.new(user: user, role: :viewer)

    if membership.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append("project_memberships_tbody", partial: "project_memberships/row", locals: { membership: membership, project: @project }),
            turbo_stream.replace("project_membership_message", partial: "project_memberships/success_message", locals: { email: user.email })
          ]
        end
        format.html { redirect_to project_path(@project), notice: "Project shared with #{user.email}." }
      end
    else
      respond_with_membership_error(membership.errors.full_messages.to_sentence)
    end
  end

  def destroy
    membership_identifier = params[:uuid] || params[:id]
    membership = @project.project_memberships.find_by!(uuid: membership_identifier)
    membership.destroy!

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(membership) }
      format.html { redirect_to project_path(@project), notice: "Access removed." }
    end
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

  def respond_with_membership_error(message)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("project_membership_message",
          partial: "project_memberships/error_message",
          locals: { message: message }), status: :unprocessable_entity
      end
      format.html { redirect_to project_path(@project), alert: message }
    end
  end
end

class ProjectMembershipsController < ApplicationController
  include ProjectScope

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

    membership = @project.project_memberships.new(user: user, role: membership_role)

    if membership.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append("project_memberships_tbody", partial: "project_memberships/row", locals: { membership: membership, project: @project }),
            turbo_stream.replace("project_membership_message", partial: "project_memberships/success_message", locals: { email: user.email })
          ]
        end
        format.html { redirect_to settings_project_path(@project, section: "team"), notice: "Project shared with #{user.email}." }
      end
    else
      respond_with_membership_error(membership.errors.full_messages.to_sentence)
    end
  end

  def update
    membership = @project.project_memberships.find_by!(uuid: params[:uuid] || params[:id])

    if membership.update(role: membership_role)
      assignment_summary = ProjectAssignmentSummary.new(@project)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            membership,
            partial: "project_memberships/row",
            locals: { membership: membership, project: @project, assignment_summary: assignment_summary }
          )
        end
        format.html { redirect_to settings_project_path(@project, section: "team"), notice: "Member role updated." }
      end
    else
      respond_with_membership_error(membership.errors.full_messages.to_sentence)
    end
  end

  def destroy
    membership_identifier = params[:uuid] || params[:id]
    membership = @project.project_memberships.find_by!(uuid: membership_identifier)
    membership.destroy!
    assignment_summary = ProjectAssignmentSummary.new(@project)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(membership),
          turbo_stream.replace(
            "project_assignment_summary",
            partial: "projects/assignment_summary",
            locals: { assignment_summary: assignment_summary }
          )
        ]
      end
      format.html { redirect_to settings_project_path(@project, section: "team"), notice: "Access removed." }
    end
  end

  private

  def set_project
    @project = current_user.manageable_projects.find_by!(uuid: project_uuid_param)
  end

  def membership_params
    params.require(:project_membership).permit(:email, :role)
  end

  def membership_role
    ProjectMembership.normalize_role(membership_params[:role])
  end

  def redirect_with_alert(message)
    redirect_to settings_project_path(@project, section: "team"), alert: message
  end

  def respond_with_membership_error(message)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("project_membership_message",
          partial: "project_memberships/error_message",
          locals: { message: message }), status: :unprocessable_content
      end
      format.html { redirect_to settings_project_path(@project, section: "team"), alert: message }
    end
  end
end

# frozen_string_literal: true

# The header setup chip, served as a lazy Turbo Frame so reading setup evidence
# never slows the page it appears on. The summary behind it is shared and cached.
class ProjectSetupChipsController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    return redirect_to(setup_project_path(@project)) unless turbo_frame_request?
    return head(:no_content) if @project.archived? || @project.purge_pending?

    render partial: "projects/setup_chip", locals: { project: @project, summary: ProjectSetupSummary.for(@project) }
  end
end

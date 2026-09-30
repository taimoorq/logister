# frozen_string_literal: true

# Records, or undoes, a project manager's decision that an optional setup step
# is not needed. Completion is never recorded here; it comes from evidence.
class ProjectSetupSkipsController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_managed_project

  def create
    step = @project.setup_steps.find_or_initialize_by(key: params.require(:key).to_s)
    step.status = "skipped"
    step.decided_by_user = current_user

    if step.save
      ProjectSetupSummary.expire(@project)
      definition = ProjectSetupCatalog.step(step.key)
      redirect_to skip_redirect_path(step),
                  notice: "#{definition.label} marked as not needed. You can undo this from Setup."
    else
      redirect_to setup_project_path(@project), alert: step.errors.full_messages.to_sentence
    end
  end

  # Skipping from inside a path moves on to the next step; from the hub it stays.
  def skip_redirect_path(step)
    return setup_project_path(@project, anchor: "step-#{step.key}") unless params[:wizard].present?

    plan = ProjectSetupPlan.for(@project, viewer: current_user)
    following = plan.item(step.key) && plan.continue_item_after(plan.item(step.key))
    following ? setup_step_project_path(@project, group: following.group_key, step: following.key) : setup_project_path(@project)
  end

  def destroy
    @project.setup_steps.where(key: params[:key].to_s).destroy_all
    ProjectSetupSummary.expire(@project)
    definition = ProjectSetupCatalog.step(params[:key])
    redirect_to setup_project_path(@project, anchor: "step-#{params[:key]}"),
                notice: "#{definition&.label || 'Step'} is back on your setup list."
  end
end

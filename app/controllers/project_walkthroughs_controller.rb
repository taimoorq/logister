# frozen_string_literal: true

# A walkthrough runs on one of the project's real issues, in the wizard layout.
# Actions inside it (assigning, closing) go through the same controllers Issues
# uses, and return here (see WalkthroughReturn).
class ProjectWalkthroughsController < ApplicationController
  include ProjectScope

  OTHER_ISSUES_LIMIT = 5

  layout "wizard"

  before_action :authenticate_user!
  before_action :set_accessible_project
  before_action :load_walkthrough
  before_action :load_group

  def index
    redirect_to walkthrough_step_project_path(@project, key: @walkthrough.key, step: @walkthrough.steps.first.key, group_uuid: @group.uuid)
  end

  def show
    @step = @walkthrough.step(params[:step]) || raise(ActiveRecord::RecordNotFound)
    @previous_step = @walkthrough.previous_step(@step)
    @next_step = @walkthrough.next_step(@step) unless @step == @walkthrough.steps.last
    @event = @group.latest_event_record
    load_step_data
    @wizard_frame = WizardFrame.new(
      context: @project.name,
      detail: "Walkthrough: #{@walkthrough.title}",
      exit_label: "Exit walkthrough",
      exit_path: inbox_project_path(@project, group_uuid: @group.uuid),
      progress_label: "#{@walkthrough.title} progress",
      done: @walkthrough.steps.index(@step),
      total: @walkthrough.rail_steps.size
    )
  end

  private

  def load_walkthrough
    @walkthrough = Walkthrough.find(params[:key]) || raise(ActiveRecord::RecordNotFound)
  end

  # The issue is in the URL so a walkthrough can be shared, refreshed, and
  # revisited after the issue's status changes.
  def load_group
    @group = if params[:group_uuid].present?
      @project.error_groups.find_by!(uuid: params[:group_uuid])
    else
      @project.error_groups.open.recent_first.first
    end
    return if @group

    redirect_to inbox_project_path(@project), alert: "The #{@walkthrough.title.downcase} walkthrough uses a real issue, and this project has no open issues yet."
  end

  def load_step_data
    case @step.key
    when :read
      @other_groups = @project.error_groups.open.where.not(id: @group.id).recent_first.limit(OTHER_ISSUES_LIMIT)
    when :shipped
      @deployment_context = ProjectDeploymentContext.call(project: @project, group: @group, event: @event)
    when :owner
      @assignable_users = @project.assignable_users
    end
  end
end

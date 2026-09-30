# frozen_string_literal: true

# A focused setup path: one step per screen, in its own layout, reached from the
# Setup hub, the header chip, and empty sections. Forms inside a step are the
# same forms Settings uses (see SetupWizardReturn), so there is one way to
# change each setting.
class ProjectSetupStepsController < ApplicationController
  include ProjectScope
  include SetupStepContext

  # The live check starts quickly, then backs off, and stops after about ten
  # minutes: 15 checks at 4s, 25 at 8s, then 23 at 15s.
  VERIFICATION_SCHEDULE = [ [ 15, 4_000 ], [ 25, 8_000 ], [ 23, 15_000 ] ].freeze
  MAX_VERIFICATION_ATTEMPTS = VERIFICATION_SCHEDULE.sum(&:first)

  def self.verification_interval(attempt)
    remaining = attempt
    VERIFICATION_SCHEDULE.each do |count, interval|
      return interval if remaining < count

      remaining -= count
    end
    VERIFICATION_SCHEDULE.last.last
  end

  layout "wizard"

  before_action :authenticate_user!
  before_action :set_accessible_project

  helper_method :verification_locals

  def index
    prepare_group_only
    target = @group.items.find(&:actionable?) || @group.items.first
    redirect_to setup_step_project_path(@project, group: @group.key, step: target.key)
  end

  def show
    prepare_setup_step(params[:group], params[:step])
    ProjectSetupSummary.expire(@project)
    load_setup_step_page
    @attempt = 0
    @live = @plan.live?
  end

  # The live check for steps done in the project's own code: a Turbo Frame that
  # re-requests itself until the evidence arrives or the attempts run out. It
  # reads only this step's evidence; the full plan is built once, on completion,
  # to say where Continue goes.
  def verification
    return redirect_to(setup_step_project_path(@project, group: params[:group], step: params[:step])) unless turbo_frame_request?

    prepare_setup_step(params[:group], params[:step], only: params[:step].to_s.to_sym)
    @attempt = params[:attempt].to_i.clamp(0, MAX_VERIFICATION_ATTEMPTS)
    load_completion_details if @item.done?

    render partial: "project_setup_steps/verification", layout: false, locals: verification_locals
  end

  private

  def prepare_group_only
    @plan = ProjectSetupPlan.for(@project, viewer: current_user)
    @group = @plan.group_view(params[:group]) || raise(ActiveRecord::RecordNotFound)
  end

  def load_completion_details
    full_plan = ProjectSetupPlan.for(@project, viewer: current_user)
    full_item = full_plan.item(@item.key)
    @next_item = full_item && full_plan.continue_item_after(full_item)
    @live = full_plan.live?
    @receipt = latest_setup_receipt if RECEIPT_STEPS.include?(@item.key)
  end

  def verification_locals
    {
      project: @project, group: @group, item: @item, receipt: @receipt, next_item: @next_item, live: @live,
      attempt: @attempt, max_attempts: MAX_VERIFICATION_ATTEMPTS,
      interval: self.class.verification_interval(@attempt)
    }
  end
end

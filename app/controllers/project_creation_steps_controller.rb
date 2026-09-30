# frozen_string_literal: true

class ProjectCreationStepsController < ApplicationController
  include ProjectsControllerData
  include Projects::SelfMonitoringContext
  include ProjectCreationWizard

  layout "wizard"

  before_action :authenticate_user!
  before_action :set_step

  def show
    prepare_creation_step(@step)
    return redirect_to(new_project_step_path("platform"), alert: "Choose what you are monitoring first.") if @step != "platform" && !platform_chosen?
    redirect_to(new_project_step_path("details", project: creation_query), alert: "Name the project first.") if @step == "retention" && @project.name.blank?
  end

  private

  def set_step
    @step = params[:step].to_s
    raise ActiveRecord::RecordNotFound unless CREATION_STEPS.include?(@step)
  end

  def platform_chosen?
    params.dig(:project, :integration_kind).to_s.in?(Project.integration_kinds.keys)
  end

  def creation_query
    creation_attributes.slice("integration_kind", "description")
  end
end

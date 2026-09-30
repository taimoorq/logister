# frozen_string_literal: true

# Lets a form that lives inside a setup wizard step send the person back to that
# step after it is submitted. The wizard adds a hidden `setup_return` field
# ("group/step"); the same form in Settings does not, so it behaves as before.
#
# The value is only honored when it names a step this project's setup actually
# contains, so it can never redirect anywhere else.
module SetupWizardReturn
  extend ActiveSupport::Concern
  include SetupStepContext

  private

  def setup_return_path
    return @setup_return_path if defined?(@setup_return_path)

    group, step = params[:setup_return].to_s.split("/", 2)
    @setup_return_path = if setup_return_step?(group, step)
      setup_step_project_path(@project, group: group, step: step)
    end
  end

  # For a validation failure: re-render the wizard step with the submitted
  # values and a 422, instead of rendering the Settings page. Returns true when
  # it handled the response.
  def render_setup_return_with_errors(alert)
    return false unless setup_return_path

    group, step = params[:setup_return].to_s.split("/", 2)
    prepare_setup_step(group, step)
    load_setup_step_page
    @attempt = 0
    @live = @plan.live?
    flash.now[:alert] = alert.presence || "That could not be saved."
    render "project_setup_steps/show", layout: "wizard", status: :unprocessable_content
    true
  end

  def setup_return_step?(group, step)
    return false if @project.blank? || group.blank? || step.blank?

    experience = @project.integration_definition.default_experience_key
    ProjectSetupCatalog.steps_for(experience).any? { |candidate| candidate.group_key.to_s == group && candidate.key.to_s == step }
  end
end

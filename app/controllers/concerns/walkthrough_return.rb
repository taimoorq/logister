# frozen_string_literal: true

# Lets an action taken inside a walkthrough step (assigning or closing an issue)
# return to the walkthrough instead of Issues. The walkthrough adds a hidden
# `walkthrough_return` field ("walkthrough/step"); Issues does not, so it behaves
# as before. The value is only honored when it names a real walkthrough step.
module WalkthroughReturn
  extend ActiveSupport::Concern

  private

  def walkthrough_return_path
    return @walkthrough_return_path if defined?(@walkthrough_return_path)

    key, step = params[:walkthrough_return].to_s.split("/", 2)
    walkthrough = Walkthrough.find(key)
    @walkthrough_return_path = if walkthrough&.step(step) && @project && @group
      walkthrough_step_project_path(@project, key: walkthrough.key, step: step, group_uuid: @group.uuid)
    end
  end
end

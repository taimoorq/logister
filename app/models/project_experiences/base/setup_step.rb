# frozen_string_literal: true

class ProjectExperiences::Base::SetupStep < Data.define(:key, :label, :icon, :state, :stage, :detail, :action_key)
  STATES = %i[complete partial pending stale blocked failed not_applicable].freeze
  STAGES = %i[connect verify_delivery improve_evidence external_sources].freeze

  def initialize(key:, label:, icon:, state:, stage:, detail:, action_key: nil)
    raise ArgumentError, "Unknown setup state: #{state}" unless STATES.include?(state.to_sym)
    raise ArgumentError, "Unknown setup stage: #{stage}" unless STAGES.include?(stage.to_sym)

    super(key: key.to_sym, label:, icon: icon.to_sym, state: state.to_sym, stage: stage.to_sym, detail:, action_key: action_key&.to_sym)
    freeze
  end

  def complete
    %i[complete not_applicable].include?(state)
  end

  def state_label
    {
      complete: "Complete",
      partial: "Partial",
      pending: "Not verified",
      stale: "Stale",
      blocked: "Blocked",
      failed: "Failed",
      not_applicable: "Not applicable"
    }.fetch(state)
  end
end

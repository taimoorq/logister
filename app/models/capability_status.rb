# frozen_string_literal: true

class CapabilityStatus < Data.define(
  :key,
  :state,
  :provenance,
  :observed_at,
  :evidence_count,
  :reason,
  :action_key
)
  STATES = %i[unsupported available unconfigured configured partial blocked stale failed not_applicable].freeze

  def initialize(key:, state:, provenance:, observed_at: nil, evidence_count: nil, reason: nil, action_key: nil)
    normalized_state = state.to_sym
    raise ArgumentError, "Unknown capability state: #{state}" unless STATES.include?(normalized_state)

    super(
      key: key.to_sym,
      state: normalized_state,
      provenance: provenance.to_sym,
      observed_at: observed_at,
      evidence_count: evidence_count,
      reason: reason,
      action_key: action_key&.to_sym
    )
    freeze
  end

  def supported?
    state != :unsupported
  end

  def usable?
    %i[available configured].include?(state)
  end
end

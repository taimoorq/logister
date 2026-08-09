# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectExperienceDefinition do
  EXPECTED_FAMILIES = {
    server: :server_application,
    edge: :edge_site,
    android: :mobile_application,
    ios: :mobile_application,
    custom: :custom_telemetry
  }.freeze

  it "defines each current experience family deliberately" do
    expect(described_class.all.to_h { |definition| [ definition.key, definition.family_key ] }).to eq(EXPECTED_FAMILIES)
    expect(described_class.validate!).to be(true)
  end

  it "resolves only profiles that implement the shared experience contract" do
    expect(described_class.all).to all(be_frozen)

    described_class.all.each do |definition|
      expect(definition.profile_class).to be <= ProjectExperiences::Base
      expect(definition.capability_loader_class).to be <= ProjectCapabilityLoaders::Static
      expect(definition.product_capabilities).to be_frozen
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectExperience do
  it "registers every supported project kind with a safe generic fallback" do
    Project.integration_kinds.each_key do |kind|
      profile = described_class.for(Project.new(integration_kind: kind))

      expect(profile).to be_a(ProjectExperiences::Base)
      expect(profile.detail_sections(event: nil, occurrences_count: 0, related_logs_count: 0)).not_to be_empty
    end
  end

  it "exposes Android capabilities and an allow-listed mobile detail contract" do
    profile = described_class.for(Project.new(integration_kind: "android"))

    expect(profile.key).to eq(:android)
    expect(profile.capabilities).to include(:mobile, :release_aware, :device_context, :structured_stacktrace)
    expect(profile.detail_sections(event: nil, occurrences_count: 3, related_logs_count: 1).map(&:key)).to eq(
      %i[stacktrace trail occurrences app_device raw]
    )
    expect(profile.normalize_detail_tab("context")).to eq("stacktrace")
  end

  it "keeps existing server integrations on the generic stack partials" do
    event = Struct.new(:log?).new(false)

    expect(described_class.for(Project.new(integration_kind: "ruby")).stacktrace_partial(event)).to eq("project_events/ruby_stacktrace")
    expect(described_class.for(Project.new(integration_kind: "python")).stacktrace_partial(event)).to eq("project_events/python_stacktrace")
  end
end

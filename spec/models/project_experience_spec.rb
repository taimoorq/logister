# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectExperience do
  EXPECTED_PROFILE_BY_INTEGRATION = {
    "ruby" => ProjectExperiences::Generic,
    "cfml" => ProjectExperiences::Generic,
    "javascript" => ProjectExperiences::Generic,
    "python" => ProjectExperiences::Generic,
    "dotnet" => ProjectExperiences::Generic,
    "cloudflare_pages" => ProjectExperiences::Generic,
    "android" => ProjectExperiences::Android,
    "ios" => ProjectExperiences::Ios,
    "http_api" => ProjectExperiences::Generic
  }.freeze

  it "registers every supported project kind with an explicit profile" do
    expect(described_class.registered_kinds).to contain_exactly(*Project.integration_kinds.keys)
    expect(described_class.validate_registry!).to be(true)

    Project.integration_kinds.each_key do |kind|
      profile = described_class.for(Project.new(integration_kind: kind))

      expect(profile).to be_a(EXPECTED_PROFILE_BY_INTEGRATION.fetch(kind))
      expect(profile.detail_sections(event: nil, occurrences_count: 0, related_logs_count: 0)).not_to be_empty
    end
  end

  it "raises for an unknown integration instead of silently falling back" do
    expect { described_class.definition_for("future_sdk") }.to raise_error(KeyError)
  end

  it "keeps product support query-free even for mobile profiles" do
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      queries << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      %w[android ios].each do |kind|
        profile = described_class.for(Project.new(integration_kind: kind))
        expect(profile.capabilities).to include(:mobile, :session_health, :distribution_store)
      end
    end

    expect(queries).to be_empty
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

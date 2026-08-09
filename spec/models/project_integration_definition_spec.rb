# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectIntegrationDefinition do
  EXPECTED_EXPERIENCE_BY_INTEGRATION = {
    "ruby" => :server,
    "cfml" => :server,
    "javascript" => :server,
    "python" => :server,
    "dotnet" => :server,
    "cloudflare_pages" => :edge,
    "android" => :android,
    "ios" => :ios,
    "http_api" => :custom
  }.freeze

  EXPECTED_PICKER_ORDER = %w[
    http_api cloudflare_pages android ios ruby dotnet javascript python cfml
  ].freeze

  it "defines every persisted integration exactly once with an explicit experience" do
    expect(described_class.keys).to contain_exactly(*Project.integration_kinds.keys)
    expect(described_class.all.to_h { |definition| [ definition.key, definition.default_experience_key ] }).to eq(
      EXPECTED_EXPERIENCE_BY_INTEGRATION
    )
    expect(described_class.validate!).to be(true)
  end

  it "keeps definitions and their compatibility lists immutable" do
    expect(described_class.all).to be_frozen
    expect(described_class.all).to all(be_frozen)
    expect(described_class.all.map(&:allowed_experience_keys)).to all(be_frozen)
  end

  it "keeps project creation order explicit and stable" do
    expect(described_class.all_for_picker.map(&:key)).to eq(EXPECTED_PICKER_ORDER)
  end

  it "raises for an unregistered integration instead of silently using a generic definition" do
    expect { described_class.fetch("future_sdk") }.to raise_error(KeyError)
  end

  it "reads static integration and experience definitions without querying the database" do
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      queries << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      described_class.all_for_picker.each do |integration|
        ProjectExperienceDefinition.fetch(integration.default_experience_key)
      end
    end

    expect(queries).to be_empty
  end
end

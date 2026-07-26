# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorOccurrenceDimensions do
  let(:project) { create(:project, :android) }
  let(:event) do
    build(
      :ingest_event,
      project: project,
      context: {
        "platform" => "android",
        "release" => "1.4.0+42",
        "session_id" => "session-raw",
        "user_id" => "user-raw",
        "installation_id_hash" => "sdk-pseudonym",
        "app_version" => "1.4.0",
        "build_number" => "42",
        "device_model" => "Pixel 8",
        "os_version" => "15",
        "android_api_level" => 35,
        "in_foreground" => true,
        "exception" => { "type" => "java.lang.IllegalStateException" }
      }
    )
  end

  it "materializes query dimensions and project-scoped hashes without raw identifiers" do
    attributes = described_class.new(event).attributes

    expect(attributes).to include(
      mechanism: "handled_exception",
      release: "1.4.0+42",
      foreground: true,
      telemetry_schema_version: 1
    )
    expect(attributes.fetch(:dimensions)).to include(
      "app_version" => "1.4.0",
      "build_number" => "42",
      "device_model" => "Pixel 8",
      "os_version" => "15",
      "api_level" => "35"
    )
    expect(attributes.values_at(:session_hash, :installation_hash, :user_hash)).to all(match(/\A[0-9a-f]{64}\z/))
    expect(attributes.to_json).not_to include("session-raw", "sdk-pseudonym", "user-raw")
  end
end

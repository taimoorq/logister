# frozen_string_literal: true

require "rails_helper"

RSpec.describe MobileArtifactCoverageRefreshJob, type: :job do
  it "re-materializes server-owned iOS coverage after artifact verification" do
    project = create(:project, :ios)
    api_key = create(:api_key, project: project, user: project.user)
    artifact = create(
      :apple_symbol_artifact,
      project: project,
      app_identifier: "com.acme.shop",
      version_code: "310",
      binary_uuid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      architecture: "arm64",
      status: "uploaded"
    )
    event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      context: {
        "platform" => "ios",
        "app" => { "identifier" => "com.acme.shop", "version_code" => "310" },
        "device" => { "architecture" => "arm64" },
        "exception" => { "stacktrace" => [ {
          "image" => "AcmeShop",
          "image_uuid" => artifact.binary_uuid,
          "address" => "0x1000",
          "application_frame" => true
        } ] }
      }
    )
    ErrorGroupingService.call(event)
    occurrence = event.error_occurrence
    expect(occurrence.dimensions["symbolication_status"]).to eq("verification_pending")

    artifact.update!(status: "verified")
    described_class.perform_now(project.id, "ios")

    expect(occurrence.reload.dimensions["symbolication_status"]).to eq("artifact_matched")
  end
end

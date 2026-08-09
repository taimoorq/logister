# frozen_string_literal: true

require "rails_helper"

RSpec.describe MobileArtifactCoverageRefreshJob, type: :job do
  it "refreshes derived Android frames without changing the issue identity" do
    project = create(:project, :android)
    event = create(
      :ingest_event,
      project: project,
      context: {
        "platform" => "android",
        "app" => { "package_name" => "com.acme.shop", "version_code" => "42" },
        "exception" => {
          "type" => "java.lang.IllegalStateException",
          "stacktrace" => [ { "class_name" => "a", "method_name" => "b", "line_number" => 1 } ]
        }
      }
    )
    group = ErrorGroupingService.call(event)
    original_fingerprint = group.fingerprint
    create(:android_mapping_file, project: project, version_code: "42")

    described_class.perform_now(project.id, "android")

    expect(project.mobile_event_enrichments.android_mapping.find_by!(event_uuid: event.uuid).status).to eq("complete")
    expect(group.reload.fingerprint).to eq(original_fingerprint)
    expect(group.grouping_evidence).to be_present
  end

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

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


  it "materializes searchable Apple diagnostic and cohort dimensions" do
    ios_project = create(:project, :ios)
    payload = JSON.parse(Rails.root.join("spec/fixtures/files/ios_error_payload.json").read)
    ios_event = build(:ingest_event, project: ios_project, context: payload.fetch("context"))

    dimensions = described_class.new(ios_event).attributes.fetch(:dimensions)

    expect(dimensions).to include(
      "app_identifier" => "com.acme.shop",
      "apple_platform" => "ios",
      "architecture" => "arm64",
      "diagnostic_source" => "sdk",
      "diagnostic_kind" => "reported_error",
      "symbolication_status" => "symbols_included",
      "exception_type" => "CheckoutError",
      "culprit" => "CheckoutViewModel.submit(_:)"
    )
  end

  it "materializes one canonical iOS diagnostic measurement without changing its unit" do
    ios_project = create(:project, :ios)
    ios_event = build(
      :ingest_event,
      project: ios_project,
      context: {
        "platform" => "ios",
        "diagnostic" => {
          "source" => "metrickit",
          "kind" => "excessive_disk_writes",
          "measurements" => {
            "total_bytes_written" => { "value" => 1_610_612_736, "unit" => "bytes" }
          }
        },
        "error" => { "mechanism" => "resource_diagnostic" }
      }
    )

    dimensions = described_class.new(ios_event).attributes.fetch(:dimensions)

    expect(dimensions).to include(
      "diagnostic_measurement" => "total_bytes_written",
      "diagnostic_measurement_value" => "1610612736.0",
      "diagnostic_measurement_unit" => "bytes"
    )
  end

  it "materializes a bounded raw app call-path variant without derived symbols" do
    ios_project = create(:project, :ios)
    payload = JSON.parse(Rails.root.join("spec/fixtures/files/ios_error_payload.json").read)
    frames = payload.dig("context", "exception", "threads", 0, "frames")
    frames[0].merge!(
      "image_uuid" => "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      "relative_address" => "4672.0"
    )
    frames[1].merge!(
      "image" => "AcmeCheckoutKit",
      "image_uuid" => "FFFFFFFF-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      "relative_address" => "0x28",
      "symbol" => "CheckoutCoordinator.finish() + 12",
      "application_frame" => true
    )
    ios_event = build(:ingest_event, project: ios_project, context: payload.fetch("context"))

    dimensions = described_class.new(ios_event).attributes.fetch(:dimensions)

    expect(dimensions.fetch("variant_key")).to match(/\A[0-9a-f]{64}\z/)
    expect(dimensions.fetch("variant_label")).to eq("CheckoutViewModel.submit(_:) → CheckoutCoordinator.finish()")
    expect(dimensions.fetch("variant_frame_count")).to eq("2")
  end

  it "materializes server-owned evidence facets without copying receipt timestamps" do
    normalized = TelemetryEvidenceNormalizer.normalize(
      context: {
        "platform" => "android",
        "diagnostic" => { "source" => "application_exit_info", "kind" => "anr" },
        "error" => { "capture_source" => "historical_exit", "fatal" => false }
      },
      client_occurred_at: 1.hour.ago,
      received_at: Time.current
    )
    evidence_event = build(:ingest_event, project: project, context: normalized.context)

    dimensions = described_class.new(evidence_event).attributes.fetch(:dimensions)

    expect(dimensions).to include(
      "evidence_source" => "application_exit_info",
      "evidence_kind" => "event_payload",
      "time_precision" => "exact",
      "identity_scope" => "occurrence",
      "capture_mode" => "historical_exit",
      "fatality" => "nonfatal"
    )
    expect(dimensions.keys).not_to include("received_at")
  end

  it "derives bounded session age only from exact source timing" do
    occurred_at = Time.zone.parse("2026-08-09 12:00:04")
    exact = build(
      :ingest_event,
      project:,
      occurred_at:,
      context: {
        "session" => { "id" => "session-1", "started_at" => "2026-08-09T12:00:00Z" },
        "telemetry_evidence" => {
          "time" => { "precision" => "exact", "occurred_at" => occurred_at.iso8601 }
        }
      }
    )
    interval = build(
      :ingest_event,
      project:,
      occurred_at:,
      context: exact.context.deep_merge(
        "telemetry_evidence" => { "time" => { "precision" => "reporting_interval" } }
      )
    )

    expect(described_class.new(exact).attributes.fetch(:dimensions)).to include(
      "session_started_at" => "2026-08-09T12:00:00Z",
      "session_age_ms" => "4000"
    )
    expect(described_class.new(interval).attributes.fetch(:dimensions)).not_to have_key("session_age_ms")
  end
end

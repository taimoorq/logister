# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectInbox::RowPresenter do
  def event_with_evidence(project:, precision:, occurred_at: nil, reporting_start: nil, reporting_end: nil, received_at:)
    create(
      :ingest_event,
      project:,
      occurred_at: occurred_at || reporting_end || received_at,
      context: {
        "platform" => "android",
        "error" => { "mechanism" => "unhandled_exception" },
        "exception" => { "type" => "java.lang.IllegalStateException", "stacktrace" => [] },
        "telemetry_evidence" => {
          "schema_version" => 1,
          "source" => "sdk",
          "kind" => "unhandled_exception",
          "fatality" => "fatal",
          "time" => {
            "precision" => precision,
            "occurred_at" => occurred_at&.utc&.iso8601,
            "reporting_start" => reporting_start&.utc&.iso8601,
            "reporting_end" => reporting_end&.utc&.iso8601,
            "received_at" => received_at.utc.iso8601
          }.compact
        }
      }
    )
  end

  it "shows only the highest attention signal and keeps workflow and failure type separate" do
    project = create(:project, :android)
    group = create(:error_group, project:, regression_count: 2, created_at: 10.minutes.ago)
    event = event_with_evidence(project:, precision: "exact", occurred_at: 2.hours.ago, received_at: 5.minutes.ago)
    row = described_class.new(project:, group:, event:)

    expect(row.attention_signal).to eq("Regressed")
    expect(row.failure_type_label).to eq("Fatal")
    expect(row.fatality_label).to be_nil
    expect(row.workflow_label).to eq("Open")
    expect(row.signal_labels).to eq([ "Regressed", "Fatal" ])
  end

  it "adds the current regression reason and proof clock without creating another signal badge" do
    project = create(:project, :android)
    proof_at = 3.hours.ago.change(usec: 0)
    group = create(
      :error_group,
      project:,
      regression_count: 1,
      current_regression: {
        "reason" => "after_ignored",
        "time_precision" => "reporting_interval",
        "proof_at" => proof_at.iso8601,
        "release" => "1.4.0+42"
      }
    )
    event = event_with_evidence(project:, precision: "exact", occurred_at: 2.hours.ago, received_at: 5.minutes.ago)

    row = described_class.new(project:, group:, event:)

    expect(row.attention_signal).to eq("Regressed")
    expect(row.attention_detail_label).to include("after mute", "reporting interval began")
    expect(row.signal_labels).to eq([ "Regressed", "Fatal" ])
    expect(row.accessibility_label).to include("after mute")
  end

  it "uses the evidence clock rather than presenting every receipt as an occurrence" do
    project = create(:project, :android)
    group = create(:error_group, project:)
    now = Time.current.change(usec: 0)

    exact = described_class.new(
      project:,
      group:,
      event: event_with_evidence(project:, precision: "exact", occurred_at: now - 2.days, received_at: now - 5.minutes)
    )
    interval = described_class.new(
      project:,
      group:,
      event: event_with_evidence(project:, precision: "reporting_interval", reporting_start: now - 3.days, reporting_end: now - 2.days, received_at: now - 5.minutes)
    )
    received = described_class.new(
      project:,
      group:,
      event: event_with_evidence(project:, precision: "received_only", received_at: now - 5.minutes)
    )

    expect(exact.recency_label).to start_with("occurred")
    expect(exact.recency_label).not_to include("5 minutes")
    expect(interval.recency_label).to start_with("reported through")
    expect(received.recency_label).to start_with("received")
  end

  it "labels partial identity coverage beside the affected-installation count" do
    project = create(:project, :android)
    metric = ErrorGroupImpactSummary::Metric.new(value: 27, state: :partial, sampled_events: 40, total_events: 100)
    unavailable = ErrorGroupImpactSummary::Metric.new(value: nil, state: :not_collected, sampled_events: 0, total_events: 100)
    impact = Struct.new(:installations, :sessions).new(metric, unavailable)
    group = create(:error_group, project:)
    event = event_with_evidence(project:, precision: "received_only", received_at: Time.current)

    row = described_class.new(project:, group:, event:, impact:)

    expect(row.impact_label).to eq("27 installations")
    expect(row.impact_coverage_label).to eq("partial coverage")
    expect(row.accessibility_label).to include("27 installations", "partial coverage", "Button")
  end

  it "uses server-derived Apple symbols while keeping successful evidence quality quiet" do
    project = create(:project, :ios)
    group = create(:error_group, project:, title: "Address-only crash")
    binary_uuid = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    event = create(
      :ingest_event,
      project:,
      context: {
        "platform" => "ios",
        "diagnostic" => { "kind" => "crash", "source" => "sdk" },
        "app" => { "identifier" => "com.acme.shop", "version_code" => "42" },
        "device" => { "architecture" => "arm64" },
        "exception" => { "type" => "EXC_BAD_ACCESS", "stacktrace" => [ {
          "image" => "AcmeShop",
          "image_uuid" => binary_uuid,
          "address" => "0x100001234",
          "application_frame" => true
        } ] }
      }
    )
    artifact = create(
      :apple_symbol_artifact,
      project:,
      app_identifier: "com.acme.shop",
      version_code: "42",
      binary_uuid:,
      architecture: "arm64",
      status: "verified"
    )
    enrichment = create(
      :mobile_event_enrichment,
      :apple_symbolication,
      project:,
      event_uuid: event.uuid,
      event_occurred_at: event.occurred_at,
      artifact_type: "AppleSymbolArtifact",
      artifact_uuid: artifact.uuid,
      artifact_checksum_sha256: artifact.checksum_sha256,
      data: {
        "artifacts" => [ { "uuid" => artifact.uuid, "checksum_sha256" => artifact.checksum_sha256 } ],
        "resolved_frame_count" => 1,
        "frames" => [ {
          "image" => "AcmeShop",
          "image_uuid" => binary_uuid,
          "address" => "0x100001234",
          "qualified_method" => "CheckoutStore.commit()",
          "symbol_identity" => "CheckoutStore.commit()",
          "method_name" => "CheckoutStore.commit()",
          "file" => "CheckoutStore.swift",
          "line_number" => 84,
          "application_frame" => true,
          "symbolicated" => true
        } ]
      }
    )
    coverage = AppleSymbolCoverage.call(project:, event:, artifacts: [ artifact ], enrichment:)

    row = described_class.new(project:, group:, event:, symbol_coverage: coverage)

    expect(row.headline).to include("EXC_BAD_ACCESS", "CheckoutStore.commit()")
    expect(row.supporting_label).to include("CheckoutStore.swift:84")
    expect(row.artifact_quality_label).to be_nil
  end
end

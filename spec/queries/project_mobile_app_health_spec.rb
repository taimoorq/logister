# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectMobileAppHealth do
  it "keeps iOS diagnostic kinds separate from app-supplied activity" do
    project = create(:project, :ios)
    diagnostic_event = create(
      :ingest_event,
      project: project,
      context: {
        "platform" => "ios",
        "diagnostic" => { "source" => "metrickit", "kind" => "cpu_exception", "measurements" => { "total_cpu_time_seconds" => 98 } },
        "app" => { "version_code" => "310" },
        "telemetry_evidence" => { "schema_version" => 1, "source" => "metrickit", "evidence_kind" => "sampled_call_tree", "time" => { "precision" => "reporting_interval" } }
      }
    )
    occurrence = create(:error_occurrence, error_group: create(:error_group, project: project), ingest_event: diagnostic_event, mechanism: "unhandled_exception")
    occurrence.update!(dimensions: { "diagnostic_kind" => "cpu_exception", "diagnostic_source" => "metrickit", "build_number" => "310", "time_precision" => "reporting_interval" })
    create(:ingest_event, :metric, project: project, context: { "app" => { "screen" => "Checkout" } })
    create(:ingest_event, :transaction, project: project, context: { "duration_ms" => 240, "app" => { "screen" => "Checkout" } })

    health = described_class.new(project).call

    expect(health.diagnostics.sole.kind).to eq("cpu_exception")
    expect(health.diagnostics.sole).to have_attributes(
      sources: [ "metrickit" ],
      builds: [ "310" ],
      time_precisions: [ "reporting_interval" ],
      evidence_role: "Sampled call tree",
      measurement: "98 s CPU"
    )
    expect(health.activity_counts.fetch("metric")).to eq(1)
    expect(health.activity_metrics.find { |metric| metric.key == :transaction_p95 }).to have_attributes(value: 240.0, coverage: :complete)
    expect(health.activity_metrics.find { |metric| metric.key == :screen_context }).to have_attributes(value: 2, coverage: :complete)
  end

  it "does not infer missing Android diagnostic evidence as zero health incidents" do
    health = described_class.new(create(:project, :android)).call

    expect(health.diagnostics).to be_empty
    expect(health.activity_counts).to be_empty
  end
end

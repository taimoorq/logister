# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEvents::IosEventPresenter do
  subject(:presenter) { described_class.new(event) }

  let(:payload) { JSON.parse(Rails.root.join("spec/fixtures/files/ios_error_payload.json").read) }
  let(:event) { Struct.new(:context, :message).new(payload.fetch("context"), payload.fetch("message")) }

  it "reads Apple symbols and canonical mobile context" do
    expect(presenter.exception_type).to eq("CheckoutError")
    expect(presenter.mechanism_label).to eq("Reported error")
    expect(presenter.diagnostic_source_label).to eq("Logister SDK")
    expect(presenter.fatal?).to be(false)
    expect(presenter.symbolication_label).to eq("Symbols included")
    expect(presenter.triggered_thread).to include(name: "Reporting thread", role: "reporting", triggered: false)
    expect(presenter.failure_type_label).to eq("Reported error")
    expect(presenter.technical_signature).to include("CheckoutError", "CheckoutViewModel.submit(_:)")
    expect(presenter.top_in_app_frame).to include(
      image: "AcmeShop",
      method_name: "CheckoutViewModel.submit(_:)",
      application_frame: true
    )
    expect(presenter.app_details).to include(bundle_identifier: "com.acme.shop", version_name: "4.2.0", version_code: "310")
    expect(presenter.device_details).to include(model: "iPhone17,1", family: "iPhone")
    expect(presenter.os_details).to include(name: "iOS", version: "19.0")
  end

  it "uses diagnostic kind before transport mechanism for non-crash MetricKit evidence" do
    cpu_event = Struct.new(:context, :message).new(
      {
        "diagnostic" => { "source" => "metrickit", "kind" => "cpu_exception", "measurements" => { "total_cpu_time_seconds" => 98 } },
        "error" => { "mechanism" => "unhandled_exception", "fatal" => false }
      },
      "CPU diagnostic"
    )

    cpu_presenter = described_class.new(cpu_event)

    expect(cpu_presenter.failure_type_label).to eq("Excessive CPU")
    expect(cpu_presenter.technical_signature).to eq("Excessive CPU · 98 s CPU")
    expect(cpu_presenter.fatal?).to be(false)
  end

  it "formats canonical MetricKit measurements and preserves the sampled call tree" do
    cpu_event = Struct.new(:context, :message).new(
      {
        "diagnostic" => {
          "source" => "metrickit",
          "kind" => "excessive_cpu",
          "measurements" => {
            "total_cpu_time" => { "value" => 98, "unit" => "seconds" },
            "sampled_time" => { "value" => 60, "unit" => "seconds" }
          },
          "call_stack_tree" => {
            "per_thread" => false,
            "stacks" => [ {
              "id" => "0",
              "name" => "Thread 0",
              "role" => "sampled",
              "attributed" => true,
              "sample_count" => 12,
              "root_frames" => [ {
                "image" => "AcmeShop",
                "image_uuid" => "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                "relative_address" => "0x1240",
                "application_frame" => true,
                "sample_count" => 9,
                "subframes" => [ { "image" => "UIKitCore", "relative_address" => "0x28", "application_frame" => false } ]
              } ]
            } ]
          }
        },
        "error" => { "mechanism" => "resource_diagnostic" },
        "threads" => [ { "id" => "0", "role" => "sampled", "attributed" => true, "frames" => [] } ]
      },
      "CPU diagnostic"
    )

    cpu_presenter = described_class.new(cpu_event)
    tree = cpu_presenter.call_stack_tree

    expect(cpu_presenter.mechanism_label).to eq("Resource diagnostic")
    expect(cpu_presenter.measurement_summary).to eq("98 s CPU · 60 s sampled")
    expect(tree).to include(per_thread: false)
    expect(tree.fetch(:stacks).sole).to include(role: "sampled", attributed: true, sample_count: 12.0)
    expect(tree.dig(:stacks, 0, :root_frames, 0)).to include(relative_address: "0x1240", sample_count: 9.0)
    expect(tree.dig(:stacks, 0, :root_frames, 0, :subframes, 0)).to include(relative_address: "0x28")
  end

  it "does not infer fatality for measurement diagnostics when Apple did not supply it" do
    %w[hang cpu_exception disk_write_exception launch_failure].each do |kind|
      diagnostic = described_class.new(
        Struct.new(:context, :message).new(
          { "diagnostic" => { "source" => "metrickit", "kind" => kind }, "error" => { "mechanism" => "unhandled_exception" } },
          kind
        )
      )

      expect(diagnostic.fatal?).to be(false), "expected #{kind} not to infer fatality"
    end
  end

  it "marks aggregate and memory termination evidence as non-stack-bearing" do
    %w[memory_limit_termination memory_pressure_termination aggregate_exit_metric].each do |kind|
      diagnostic = described_class.new(
        Struct.new(:context, :message).new({ "diagnostic" => { "kind" => kind } }, kind)
      )

      expect(diagnostic.stack_not_applicable?).to be(true)
      expect(diagnostic.stack_unavailable_reason).to be_present
    end
  end

  it "labels privacy-safe MetricKit diagnostics without inventing a message" do
    safe_event = Struct.new(:context, :message).new(
      {
        "diagnostic" => { "source" => "metrickit", "kind" => "crash" },
        "error" => {
          "mechanism" => "native_crash",
          "handled" => false,
          "fatal" => true,
          "capture_source" => "metrickit",
          "data_policy" => "type_and_stacktrace"
        },
        "exception" => { "type" => "MetricKit crash", "stacktrace" => [] }
      },
      nil
    )
    safe_presenter = described_class.new(safe_event)

    expect(safe_presenter.capture_source_label).to eq("MetricKit capture")
    expect(safe_presenter.exception_data_policy).to eq("type_and_stacktrace")
    expect(safe_presenter.exception_detail_redacted?).to be(true)
    expect(safe_presenter.exception_message).to be_nil
  end
end

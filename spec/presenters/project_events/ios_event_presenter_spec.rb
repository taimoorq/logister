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
    expect(presenter.triggered_thread).to include(name: "Reporting thread", triggered: true)
    expect(presenter.top_in_app_frame).to include(
      image: "AcmeShop",
      method_name: "CheckoutViewModel.submit(_:)",
      application_frame: true
    )
    expect(presenter.app_details).to include(bundle_identifier: "com.acme.shop", version_name: "4.2.0", version_code: "310")
    expect(presenter.device_details).to include(model: "iPhone17,1", family: "iPhone")
    expect(presenter.os_details).to include(name: "iOS", version: "19.0")
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

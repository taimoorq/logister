# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEvents::AndroidEventPresenter do
  subject(:presenter) { described_class.new(event) }

  let(:payload) { JSON.parse(Rails.root.join("spec/fixtures/files/android_error_payload.json").read) }
  let(:event) { Struct.new(:context, :message).new(payload.fetch("context"), payload.fetch("message")) }

  it "reads the current Android SDK exception, cause, and structured frames" do
    expect(presenter.exception_type).to eq("java.lang.IllegalStateException")
    expect(presenter.mechanism_label).to eq("Reported exception")
    expect(presenter.cause_chain.map { |entry| entry[:type] }).to eq([
      "java.lang.IllegalStateException",
      "java.io.IOException"
    ])
    expect(presenter.frames.first).to include(
      qualified_method: "com.acme.shop.checkout.CartRepository.save",
      file: "CartRepository.kt",
      line_number: 84,
      application_frame: true
    )
    expect(presenter.frames.second[:application_frame]).to be(false)
  end

  it "normalizes legacy flat app, device, and Android OS context" do
    expect(presenter.app_details).to include(
      package_name: "com.acme.shop",
      version_name: "1.4.0",
      version_code: "42",
      build_type: "release",
      screen: "Checkout"
    )
    expect(presenter.device_details).to include(manufacturer: "Google", model: "Pixel 8")
    expect(presenter.os_details).to include(name: "Android", version: "15", api_level: "35")
  end

  it "uses the deepest in-app cause frame as the stable culprit" do
    expect(presenter.top_in_app_frame).to include(
      qualified_method: "com.acme.shop.storage.CartStore.write",
      line_number: 19
    )
  end

  it "presents privacy-safe automatic capture metadata without requiring a message or cause" do
    safe_payload = JSON.parse(Rails.root.join("spec/fixtures/files/android_safe_automatic_error_payload.json").read)
    safe_payload["context"]["error"]["thread_name"] = "checkout-crash"
    safe_event = Struct.new(:context, :message).new(safe_payload.fetch("context"), safe_payload.fetch("message"))
    safe_presenter = described_class.new(safe_event)

    expect(safe_presenter.mechanism_label).to eq("Fatal")
    expect(safe_presenter.capture_source_label).to eq("Automatic capture")
    expect(safe_presenter.exception_data_policy).to eq("type_and_stacktrace")
    expect(safe_presenter.error_thread_name).to eq("checkout-crash")
    expect(safe_presenter).to be_exception_detail_redacted
    expect(safe_presenter.exception_message).to eq("java.lang.IllegalStateException")
    expect(safe_presenter.cause_chain.map { |entry| entry[:message] }).to eq([ nil ])
  end

  it "uses termination evidence instead of inventing an exception for a historical exit" do
    exit_event = Struct.new(:context, :message).new(
      {
        "error_mechanism" => "anr",
        "capture_source" => "historical_exit",
        "application_exit_reason" => 6,
        "app" => { "version_name" => "4.2.0", "version_code" => "310" }
      },
      "Android process exit: anr"
    )

    exit_presenter = described_class.new(exit_event)

    expect(exit_presenter.failure_type_label).to eq("ANR")
    expect(exit_presenter.technical_signature).to eq("ANR · 6")
    expect(exit_presenter.top_in_app_frame).to be_nil
    expect(exit_presenter.stack_not_applicable?).to be(true)
    expect(exit_presenter.application_exit_details).to include(reason: "6")
  end

  it "presents bounded ANR thread and sampled-memory evidence without inventing an exception" do
    exit_event = Struct.new(:context, :message).new(
      {
        "error_mechanism" => "anr",
        "capture_source" => "historical_exit",
        "application_exit_reason" => 6,
        "application_exit_status" => 0,
        "app" => { "package_name" => "com.acme.shop", "version_name" => "4.2.0", "version_code" => "310" },
        "diagnostic" => {
          "kind" => "anr",
          "measurements" => {
            "last_pss" => { "value" => 2_097_152, "unit" => "bytes", "precision" => "last_system_sample" },
            "last_rss" => { "value" => 4_194_304, "unit" => "bytes", "precision" => "last_system_sample" }
          },
          "thread_dump" => {
            "truncated" => true,
            "threads" => [
              {
                "name" => "main",
                "role" => "main",
                "attributed" => true,
                "frames" => [
                  { "class_name" => "com.acme.shop.CheckoutStore", "method_name" => "commit", "file_name" => "CheckoutStore.kt", "line_number" => 84, "in_app" => true },
                  { "class_name" => "android.app.ActivityThread", "method_name" => "main", "file_name" => "ActivityThread.java", "line_number" => 9000, "in_app" => false }
                ]
              }
            ]
          }
        }
      },
      "Android process exit: anr"
    )

    exit_presenter = described_class.new(exit_event)

    expect(exit_presenter.exception).to be_empty
    expect(exit_presenter.exception_type).to eq("ANR")
    expect(exit_presenter.technical_signature).to eq("ANR · com.acme.shop.CheckoutStore.commit")
    expect(exit_presenter.top_in_app_frame).to include(file: "CheckoutStore.kt", line_number: 84)
    expect(exit_presenter.stack_not_applicable?).to be(false)
    expect(exit_presenter).to be_historical_thread_dump
    expect(exit_presenter).to be_thread_dump_truncated
    expect(exit_presenter.measurement_summary).to eq("Last PSS 2 MB · Last RSS 4 MB")
    expect(exit_presenter.application_exit_details).to include(status: "0", last_pss: "2 MB", last_rss: "4 MB")
  end
end

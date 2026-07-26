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
end

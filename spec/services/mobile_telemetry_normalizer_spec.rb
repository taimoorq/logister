# frozen_string_literal: true

require "rails_helper"

RSpec.describe MobileTelemetryNormalizer do
  it "canonicalizes the current flat Android SDK vocabulary without dropping legacy fields" do
    context = described_class.normalize(
      "platform" => "android",
      "package_name" => "com.acme.shop",
      "app_version" => "1.4.0",
      "build_number" => "42",
      "device_model" => "Pixel 8",
      "os_version" => "15",
      "android_api_level" => 35,
      "session_id" => "session-123",
      "exception" => { "type" => "java.lang.IllegalStateException" }
    )

    expect(context).to include("package_name" => "com.acme.shop", "telemetry_schema_version" => 1)
    expect(context.fetch("app")).to include("package_name" => "com.acme.shop", "version_name" => "1.4.0", "version_code" => "42")
    expect(context.fetch("device")).to include("model" => "Pixel 8")
    expect(context.fetch("os")).to include("name" => "Android", "version" => "15", "api_level" => 35)
    expect(context.fetch("session")).to include("id" => "session-123")
    expect(context.fetch("error")).to include("mechanism" => "handled_exception", "handled" => true)
  end

  it "bounds breadcrumbs and removes known hardware and advertising identifiers" do
    context = described_class.normalize(
      "platform" => "android",
      "android_id" => "raw-hardware-id",
      "device" => { "advertising_id" => "ad-id", "model" => "Pixel" },
      "breadcrumbs" => 105.times.map { |index| { "message" => "step #{index}", "extra" => "discard" } }
    )

    expect(context).not_to have_key("android_id")
    expect(context.fetch("device")).not_to have_key("advertising_id")
    expect(context.fetch("breadcrumbs").size).to eq(100)
    expect(context.fetch("breadcrumbs").first).to eq("message" => "step 5")
  end

  it "normalizes iOS into the same app, device, OS, error, and correlation contract" do
    context = described_class.normalize(
      "platform" => "ios",
      "bundle_identifier" => "com.acme.shop",
      "app_version" => "4.2.0",
      "build_number" => "310",
      "device_model" => "iPhone17,1",
      "os_version" => "19.0",
      "session_id" => "session-ios-1",
      "exception" => { "type" => "CheckoutError" }
    )

    expect(context.fetch("app")).to include("package_name" => "com.acme.shop", "version_name" => "4.2.0", "version_code" => "310")
    expect(context.fetch("device")).to include("model" => "iPhone17,1")
    expect(context.fetch("os")).to include("name" => "iOS", "version" => "19.0")
    expect(context.fetch("session")).to include("id" => "session-ios-1")
    expect(context.fetch("error")).to include("mechanism" => "handled_exception", "handled" => true)
  end
end

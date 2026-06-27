# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientSubmissions::MobileTokenPolicy, type: :model do
  it "allows only mobile-safe endpoints" do
    expect(described_class.endpoint_allowed?(:ingest)).to be(true)
    expect(described_class.endpoint_allowed?(:check_in)).to be(true)
    expect(described_class.endpoint_allowed?(:deployment)).to be(false)
  end

  it "applies token-bound context when the event type is allowed" do
    mobile_token = create(:mobile_ingest_token, allowed_event_types: [ "log" ])
    context = { "screen_name" => "Checkout" }

    result = described_class.new(mobile_token).enforce_event(event_type: "log", context: context)

    expect(result).to be_allowed
    expect(context).to include(
      "platform" => mobile_token.platform,
      "service" => mobile_token.service,
      "environment" => mobile_token.environment,
      "release" => mobile_token.release,
      "session_id" => mobile_token.session_id,
      "screen_name" => "Checkout"
    )
  end

  it "rejects disallowed event types" do
    mobile_token = create(:mobile_ingest_token, allowed_event_types: [ "error" ])

    result = described_class.new(mobile_token).enforce_event(event_type: "metric", context: {})

    expect(result).not_to be_allowed
    expect(result.status).to eq(:forbidden)
    expect(result.error).to eq("Mobile ingest token cannot send this event type")
  end

  it "rejects context values that conflict with token bindings" do
    mobile_token = create(:mobile_ingest_token, service: "com.example.app")
    context = { "service" => "com.attacker.app" }

    result = described_class.new(mobile_token).enforce_event(event_type: "log", context: context)

    expect(result).not_to be_allowed
    expect(result.status).to eq(:unprocessable_content)
    expect(result.errors.join).to include("service must match")
  end
end

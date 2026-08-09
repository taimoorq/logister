# frozen_string_literal: true

require "rails_helper"

RSpec.describe IngestEventPayloadNormalizer do
  def normalized_context(event)
    params = ActionController::Parameters.new(event: event)
    normalizer = described_class.new(params:, default_environment: "production")
    event_hash = normalizer.event_hash
    normalizer.event_params(event_hash).fetch("context")
  end

  it "maps top-level transaction status into a signal-specific context field" do
    context = normalized_context(
      event_type: "transaction",
      message: "POST /checkout",
      status: 503,
      duration_ms: 182.5
    )

    expect(context).to include("transaction_status" => 503, "duration_ms" => 182.5)
    expect(context).not_to have_key("check_in_status")
  end

  it "maps top-level check-in status without classifying it as a transaction" do
    context = normalized_context(
      event_type: "check_in",
      message: "nightly-import",
      status: "ok",
      check_in_slug: "nightly-import"
    )

    expect(context).to include("check_in_status" => "ok", "check_in_slug" => "nightly-import")
    expect(context).not_to have_key("transaction_status")
  end

  it "uses event_id when the uuid alias is blank" do
    uuid = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    params = ActionController::Parameters.new(
      event: { uuid: " ", event_id: uuid, event_type: "log", message: "aliased" }
    )
    normalizer = described_class.new(params: params, default_environment: "production")
    event_hash = normalizer.event_hash

    expect(normalizer.event_params(event_hash).fetch("uuid")).to eq(uuid)
  end
end

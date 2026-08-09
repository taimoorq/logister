# frozen_string_literal: true

require "rails_helper"

RSpec.describe TelemetryPayloadLimits do
  it "accepts a normal nested telemetry envelope" do
    expect do
      described_class.validate!(
        event_type: "error",
        message: "Checkout failed",
        context: { request: { method: "POST", params: [ "one", "two" ] } }
      )
    end.not_to raise_error
  end

  it "rejects context that exceeds the depth limit" do
    context = "leaf"
    (described_class::MAX_CONTEXT_DEPTH + 1).times { context = { "nested" => context } }

    expect { described_class.validate!(context: context) }
      .to raise_error(described_class::Exceeded) { |error| expect(error.code).to eq(:context_depth) }
  end

  it "rejects oversized arrays" do
    context = { values: Array.new(described_class::MAX_ARRAY_LENGTH + 1, 1) }

    expect { described_class.validate!(context: context) }
      .to raise_error(described_class::Exceeded) { |error| expect(error.code).to eq(:array_length) }
  end

  it "rejects oversized messages independently from the total envelope" do
    message = "x" * (described_class::MAX_MESSAGE_BYTES + 1)

    expect { described_class.validate!(message: message) }
      .to raise_error(described_class::Exceeded) { |error| expect(error.code).to eq(:message_bytes) }
  end
end

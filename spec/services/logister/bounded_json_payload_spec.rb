# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::BoundedJsonPayload do
  it "returns valid JSON that never exceeds the exact byte budget" do
    payload = {
      "message" => %(quote: "#{ "x" * 500 }"),
      "nested" => Array.new(20) { { "value" => "y" * 200 } }
    }

    result = described_class.call(payload, max_bytes: 256)
    encoded = JSON.generate(result.value)

    expect(result.truncated).to be(true)
    expect(result.bytes).to eq(encoded.bytesize)
    expect(encoded.bytesize).to be <= 256
    expect(JSON.parse(encoded)).to eq(result.value)
  end

  it "preserves an in-budget payload without marking it truncated" do
    payload = { "message" => "safe", "count" => 2 }

    result = described_class.call(payload, max_bytes: 256)

    expect(result.value).to eq(payload)
    expect(result.truncated).to be(false)
    expect(result.bytes).to eq(JSON.generate(payload).bytesize)
  end
end

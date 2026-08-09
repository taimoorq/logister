# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseFailureSignature do
  it "ignores row identifiers, JSON payloads, and timestamps" do
    first = Logister::ClickhouseClient::Error.new(
      'Cannot parse row 9182736 at 2026-08-08T12:00:00.123Z: {"event_id":"cdd9c1bc-0de2-4e18-927f-3ca07133c111","value":1}'
    )
    second = Logister::ClickhouseClient::Error.new(
      'Cannot parse row 8374651 at 2026-08-09T14:22:31.555Z: {"event_id":"7274cb13-c522-4504-9c80-3b208a474eee","value":99}'
    )

    expect(described_class.call(first, kind: "event")).to eq(described_class.call(second, kind: "event"))
  end
end

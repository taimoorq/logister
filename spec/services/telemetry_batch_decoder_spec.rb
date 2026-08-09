# frozen_string_literal: true

require "rails_helper"

RSpec.describe TelemetryBatchDecoder do
  def ndjson(*events)
    events.map { |event| { event: event }.to_json }.join("\n") << "\n"
  end

  it "shares the wire-size ceiling with single-event JSON intake" do
    expect(described_class::MAX_COMPRESSED_BYTES).to eq(ClientSubmissions::RequestLimits::MAX_WIRE_BYTES)
    expect(ClientSubmissions::SingleEventBodyLimiter::MAX_BODY_BYTES).to eq(described_class::MAX_COMPRESSED_BYTES)
  end

  it "decodes gzip NDJSON event envelopes" do
    body = Zlib.gzip(ndjson(
      { uuid: SecureRandom.uuid, event_type: "log", message: "one" },
      { uuid: SecureRandom.uuid, event_type: "metric", message: "two" }
    ))

    events = described_class.call(io: StringIO.new(body), content_encoding: "gzip")

    expect(events.map { |event| event.fetch("message") }).to eq(%w[one two])
  end

  it "accepts uncompressed NDJSON" do
    events = described_class.call(
      io: StringIO.new(ndjson({ uuid: SecureRandom.uuid, event_type: "log", message: "one" }))
    )

    expect(events.sole.fetch("event_type")).to eq("log")
  end

  it "rejects batches above the event-count limit" do
    body = ndjson(*Array.new(described_class::MAX_BATCH_EVENTS + 1) do
      { uuid: SecureRandom.uuid, event_type: "log", message: "event" }
    end)

    expect { described_class.call(io: StringIO.new(body)) }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:event_count) }
  end

  it "rejects a malformed envelope with its line number" do
    expect { described_class.call(io: StringIO.new("{\"message\":\"missing event\"}\n")) }
      .to raise_error(described_class::Invalid, /line 1/) { |error| expect(error.code).to eq(:missing_event) }
  end

  it "rejects non-object envelopes and event values with controlled errors" do
    expect { described_class.call(io: StringIO.new("[]\n")) }
      .to raise_error(described_class::Invalid, /envelope object/) do |error|
        expect(error.code).to eq(:invalid_envelope)
      end
    expect { described_class.call(io: StringIO.new(%({"event":[]}\n))) }
      .to raise_error(described_class::Invalid, /event object/) do |error|
        expect(error.code).to eq(:missing_event)
      end
  end

  it "requires a nonblank valid stable identity on every envelope" do
    missing = ndjson(event_type: "log", message: "missing")
    blank = ndjson(uuid: "  ", event_id: nil, event_type: "log", message: "blank")
    invalid = ndjson(event_id: "not-a-uuid", event_type: "log", message: "invalid")

    expect { described_class.call(io: StringIO.new(missing)) }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:missing_identity) }
    expect { described_class.call(io: StringIO.new(blank)) }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:missing_identity) }
    expect { described_class.call(io: StringIO.new(invalid)) }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:invalid_identity) }
  end

  it "accepts event_id as the stable identity and rejects conflicting aliases" do
    uuid = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    events = described_class.call(
      io: StringIO.new(ndjson(event_id: uuid, event_type: "log", message: "aliased"))
    )

    expect(events.sole.fetch("event_id")).to eq(uuid)

    conflicting = ndjson(
      uuid: uuid,
      event_id: "ffffffff-eeee-4ddd-8ccc-bbbbbbbbbbbb",
      event_type: "log",
      message: "conflicting"
    )
    expect { described_class.call(io: StringIO.new(conflicting)) }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:conflicting_identity) }
  end

  it "rejects unsupported or stacked content encodings" do
    body = ndjson({ uuid: SecureRandom.uuid, event_type: "log", message: "one" })

    expect { described_class.call(io: StringIO.new(body), content_encoding: "br") }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:unsupported_encoding) }
    expect { described_class.call(io: StringIO.new(Zlib.gzip(body)), content_encoding: "br, gzip") }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:unsupported_encoding) }
  end
end

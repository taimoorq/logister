require "rails_helper"

RSpec.describe CorrelationContext do
  it "uses one precedence contract, preserves legacy IDs, and refuses conflicting aliases for matching" do
    context = { "trace_id" => "canonical", "request" => { "traceId" => "legacy", "requestId" => "req-1" } }
    ids = described_class.new(context)
    expect(ids.value("trace_id")).to eq("canonical")
    expect(ids.matchable("trace_id")).to be_nil
    expect(ids.normalized.dig("correlation", "conflicts")).to eq([ "trace_id" ])
    expect(ids.matchable("request_id")).to eq("req-1")
  end

  it "agrees with PostgreSQL on empty, invalid, nested and contradictory identifiers" do
    [ { trace_id: 123, trace: { id: "valid" } }, { trace_id: "", traceId: "old" }, { trace_id: "x", traceId: "y" }, { request: { traceId: "nested" } }, { trace_id: "x" * 129 } ].each do |context|
      sql = "SELECT #{described_class.postgres('trace_id', matchable: true)} FROM (SELECT #{ActiveRecord::Base.connection.quote(context.to_json)}::jsonb AS context) source"
      expect(ActiveRecord::Base.connection.select_value(sql)).to eq(described_class.new(context).matchable("trace_id"))
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::TelemetryProjectionSources, type: :model do
  it "separates repeated event IDs across partitions and hydrates the correct project" do
    project = create(:project)
    first = create(:ingest_event, project: project, occurred_at: Time.utc(2026, 8, 1, 0, 0, 0, 123456))
    second = create(:ingest_event, id: first.id, project: project, occurred_at: Time.utc(2026, 9, 1, 0, 0, 0, 123456))
    deliveries = [ first, second ].map { |event| delivery_reference(event) }

    sources = described_class.new(deliveries)

    expect(deliveries.map { |delivery| sources.fetch(delivery).uuid }).to eq([ first.uuid, second.uuid ])
    expect(deliveries.map { |delivery| sources.fetch(delivery).association(:project) }).to all(be_loaded)
    expect(deliveries.map { |delivery| sources.project_for(delivery).id }).to eq([ project.id, project.id ])
  end

  it "loads spans and events by their tenant and canonical reference without falling back to an ID-only lookup" do
    span = create(:trace_span)
    event = create(:ingest_event)
    deliveries = [ span, event ].map { |record| delivery_reference(record) }
    forged = delivery_reference(event)
    forged.project_id = span.project_id

    sources = described_class.new(deliveries + [ forged ])

    expect(sources.fetch(deliveries.first).uuid).to eq(span.uuid)
    expect(sources.fetch(deliveries.last).uuid).to eq(event.uuid)
    expect(sources.fetch(forged)).to be_nil
  end

  def delivery_reference(record)
    type = record.class.base_class.name
    outbox = TelemetryOutboxEvent.new(id: SecureRandom.random_number(1_000_000_000), project_id: record.project_id,
      record_type: type, record_id: record.id, recorded_at: TelemetryIdempotencyKey.recorded_at_for(record))
    TelemetryDelivery.new(project_id: record.project_id, telemetry_outbox_event: outbox)
  end
end

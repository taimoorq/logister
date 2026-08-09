# frozen_string_literal: true

require "rails_helper"

RSpec.describe TraceSpanPersistence, type: :model do
  let(:project) { create(:project) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }
  let(:attributes) do
    {
      trace_id: "trace-checkout",
      span_id: "span-root",
      name: "GET /checkout",
      kind: "server",
      duration_ms: 15.5,
      started_at: Time.current,
      context: { "environment" => "production" }
    }
  end

  around do |example|
    config = Rails.configuration.x.logister
    previous_mode = config.clickhouse_mode
    previous_enabled = config.clickhouse_enabled
    config.clickhouse_mode = "dual_write"
    config.clickhouse_enabled = true
    example.run
  ensure
    config.clickhouse_mode = previous_mode
    config.clickhouse_enabled = previous_enabled
  end

  it "persists an explicit client UUID as the span and ledger identity" do
    uuid = "bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
    result = described_class.new(
      project: project,
      api_key: api_key,
      attributes: attributes.merge(uuid: uuid)
    ).call

    expect(result.span.uuid).to eq(uuid)
    expect(result.outbox_event.client_identifier).to eq(uuid)
    expect(result.outbox_event.telemetry_deliveries.pluck(:destination)).to contain_exactly("clickhouse_span")
  end

  it "derives a stable UUID from the natural span identity and accepts retries idempotently" do
    first = described_class.new(project: project, api_key: api_key, attributes: attributes).call

    expect {
      duplicate = described_class.new(project: project, api_key: api_key, attributes: attributes).call
      expect(duplicate).to be_duplicate
      expect(duplicate.span.uuid).to eq(first.span.uuid)
    }.not_to change(TraceSpan, :count)

    expect(first.span.uuid).to eq(Logister::TelemetryIdentity.for_span(
      project_id: project.id,
      trace_id: attributes.fetch(:trace_id),
      span_id: attributes.fetch(:span_id)
    ))
    expect(TelemetryIdempotencyKey.where(project: project, client_identifier: first.span.uuid).count).to eq(1)
  end

  it "accepts a retry from immutable ledger metadata after its source is retired" do
    uuid = "cccccccc-dddd-4eee-8fff-aaaaaaaaaaaa"
    first = described_class.new(
      project: project,
      api_key: api_key,
      attributes: attributes.merge(uuid: uuid)
    ).call
    key = first.outbox_event.telemetry_idempotency_key
    accepted_metadata = key.acceptance_metadata.deep_dup

    first.outbox_event.telemetry_deliveries.update_all(status: "completed", completed_at: Time.current)
    key.update!(source_retired_at: Time.current)
    first.span.delete

    expect do
      duplicate = described_class.new(
        project: project,
        api_key: api_key,
        attributes: attributes.merge(uuid: uuid)
      ).call

      expect(duplicate).to be_duplicate
      expect(duplicate.span).to be_a(TelemetryAcceptanceTombstone)
      expect(duplicate.span).to have_attributes(uuid: uuid, id: first.span.id)
      expect(duplicate.outbox_event).to eq(first.outbox_event)
    end.not_to change(TraceSpan, :count)

    expect(key.reload.acceptance_metadata).to eq(accepted_metadata)
  end

  it "reports an identity conflict when a ledger source disappears without retirement" do
    uuid = "dddddddd-eeee-4fff-8aaa-bbbbbbbbbbbb"
    first = described_class.new(
      project: project,
      api_key: api_key,
      attributes: attributes.merge(uuid: uuid)
    ).call
    first.span.delete

    duplicate = described_class.new(
      project: project,
      api_key: api_key,
      attributes: attributes.merge(uuid: uuid)
    ).call

    expect(duplicate).not_to be_duplicate
    expect(duplicate.span).not_to be_persisted
    expect(duplicate.span.errors[:uuid]).to include("has already been used for another telemetry signal")
  end

  it "scopes an explicit source UUID to its project" do
    uuid = "eeeeeeee-ffff-4aaa-8bbb-cccccccccccc"
    other_project = create(:project)
    other_key = create(:api_key, project: other_project, user: other_project.user)

    first = described_class.new(
      project: project,
      api_key: api_key,
      attributes: attributes.merge(uuid: uuid)
    ).call
    second = described_class.new(
      project: other_project,
      api_key: other_key,
      attributes: attributes.merge(uuid: uuid)
    ).call

    expect(first).not_to be_duplicate
    expect(second).not_to be_duplicate
    expect(TraceSpan.where(uuid: uuid).pluck(:project_id)).to contain_exactly(project.id, other_project.id)
  end
end

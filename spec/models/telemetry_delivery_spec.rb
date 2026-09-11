# frozen_string_literal: true

require "rails_helper"

RSpec.describe TelemetryDelivery, type: :model do
  let(:now) { Time.current.change(usec: 0) }
  let(:project) { create(:project) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }

  around do |example|
    previous = ENV["LOGISTER_ORDERED_DELIVERY_CLAIMS"]
    example.run
  ensure
    previous.nil? ? ENV.delete("LOGISTER_ORDERED_DELIVERY_CLAIMS") : ENV["LOGISTER_ORDERED_DELIVERY_CLAIMS"] = previous
  end

  it "preserves eligibility at every status, attempt, availability and lease boundary in both query modes" do
    delivery = accept_delivery
    described_class.statuses.keys.product([ 0, 7, 8 ], [ now - 1.second, now, now + 1.second ], [ nil, now - 1.second, now, now + 1.second ]).each do |status, attempts, available_at, expires_at|
      delivery.update_columns(status: status, attempts: attempts, available_at: available_at, lease_expires_at: expires_at)
      time_is_due = case status
      when "pending", "retrying" then available_at <= now
      when "processing" then expires_at.present? && expires_at <= now
      else false
      end
      expected = attempts < 8 && time_is_due
      %w[false true].each do |mode|
        ENV["LOGISTER_ORDERED_DELIVERY_CLAIMS"] = mode
        expect(described_class.due(now: now).where(id: delivery.id).exists?).to eq(expected),
          "mode=#{mode} status=#{status} attempts=#{attempts} available_at=#{available_at} lease_expires_at=#{expires_at}"
      end
    end
  end

  it "retains destination filtering and the purge exclusion in both modes" do
    delivery = accept_delivery
    %w[false true].each do |mode|
      ENV["LOGISTER_ORDERED_DELIVERY_CLAIMS"] = mode
      expect(described_class.due(now: now, destinations: [ "clickhouse_span" ])).not_to include(delivery)
      expect(described_class.due(now: now, destinations: [ "clickhouse_event" ])).to include(delivery)
    end
    project.update_columns(purge_requested_at: now)
    %w[false true].each do |mode|
      ENV["LOGISTER_ORDERED_DELIVERY_CLAIMS"] = mode
      expect(described_class.due(now: now)).not_to include(delivery)
    end
  end

  it "orders an expired lease by availability and keeps an assigned retry group intact beyond the fresh limit" do
    ENV["LOGISTER_ORDERED_DELIVERY_CLAIMS"] = "true"
    retry_group = 3.times.map { accept_delivery }
    fresh = accept_delivery
    retry_group.each do |delivery|
      delivery.update_columns(status: "processing", attempts: 1, available_at: now - 1.hour,
        lease_expires_at: now, lease_token: SecureRandom.uuid, batch_key: "original-batch")
    end

    result = described_class.claim_batch(limit: 1, now: now)

    expect(result.map(&:id)).to match_array(retry_group.map(&:id))
    expect(result.map(&:lease_token).uniq.size).to eq(1)
    expect(result).to all(have_attributes(status: "processing", attempts: 2, batch_key: "original-batch"))
    expect(fresh.reload).to be_pending
  end

  private

  def accept_delivery
    event = IngestEventPersistence.new(
      project: project, api_key: api_key,
      attributes: { uuid: SecureRandom.uuid, event_type: "log", message: "claim boundary", occurred_at: now },
      clickhouse_writable: true, installation: nil
    ).call.outbox_event
    event.telemetry_deliveries.find_by!(destination: "clickhouse_event").tap { |delivery| delivery.update_columns(available_at: now) }
  end
end

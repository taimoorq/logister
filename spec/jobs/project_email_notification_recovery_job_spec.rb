# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEmailNotificationRecoveryJob, type: :job do
  before { ActionMailer::Base.deliveries.clear }

  it "reclaims and sends a stale notification lease" do
    now = Time.zone.parse("2026-08-08 12:00:00 UTC")
    delivery = create(:email_notification_delivery, :first_occurrence, status: "sending")
    delivery.update_column(:updated_at, now - EmailNotificationDelivery::SENDING_LEASE - 1.minute)

    described_class.perform_now(delivery.id, now.iso8601)

    expect(delivery.reload.status).to eq("sent")
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "does not compete with a live notification lease" do
    now = Time.zone.parse("2026-08-08 12:00:00 UTC")
    delivery = create(:email_notification_delivery, :first_occurrence, status: "sending")
    delivery.update_column(:updated_at, now - 1.minute)

    described_class.perform_now(delivery.id, now.iso8601)

    expect(delivery.reload.status).to eq("sending")
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end

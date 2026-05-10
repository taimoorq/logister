# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectErrorDigestJob, type: :job do
  before { ActionMailer::Base.deliveries.clear }

  it "sends one digest email for an opted-in project period" do
    period_start = Time.zone.parse("2026-05-08 00:00:00 UTC")
    period_end = Time.zone.parse("2026-05-09 00:00:00 UTC")
    project = create(:project)
    preference = create(:project_notification_preference, :daily, project: project, user: project.user)
    group = create(:error_group, project: project, title: "Checkout failed", first_seen_at: period_start + 1.hour, last_seen_at: period_start + 2.hours)
    event = create(:ingest_event, project: project, api_key: create(:api_key, project: project, user: project.user), message: "Checkout failed", occurred_at: period_start + 2.hours)
    create(:error_occurrence, error_group: group, ingest_event: event, occurred_at: event.occurred_at)

    described_class.perform_now(preference.id, period_start.iso8601, period_end.iso8601, "daily")
    described_class.perform_now(preference.id, period_start.iso8601, period_end.iso8601, "daily")

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.first.subject).to include("Daily error digest")
    delivery = EmailNotificationDelivery.sent.find_by(notification_kind: "daily_digest")
    expect(delivery.metadata["total_occurrences"]).to eq(1)
    expect(delivery.period_start_at).to eq(period_start)
  end

  it "skips and deduplicates empty digests by default" do
    project = create(:project)
    preference = create(:project_notification_preference, :daily, project: project, user: project.user)

    described_class.perform_now(
      preference.id,
      Time.zone.parse("2026-05-08 00:00:00 UTC").iso8601,
      Time.zone.parse("2026-05-09 00:00:00 UTC").iso8601,
      "daily"
    )

    expect(ActionMailer::Base.deliveries).to be_empty
    delivery = EmailNotificationDelivery.sole
    expect(delivery.status).to eq("skipped")
    expect(delivery.last_error).to eq("No error occurrences in digest period")
  end

  it "does not send digests for archived projects" do
    period_start = Time.zone.parse("2026-05-08 00:00:00 UTC")
    period_end = Time.zone.parse("2026-05-09 00:00:00 UTC")
    project = create(:project)
    preference = create(:project_notification_preference, :daily, project: project, user: project.user)
    group = create(:error_group, project: project, title: "Archived digest error", first_seen_at: period_start + 1.hour, last_seen_at: period_start + 2.hours)
    event = create(:ingest_event, project: project, api_key: create(:api_key, project: project, user: project.user), message: "Archived digest error", occurred_at: period_start + 2.hours)
    create(:error_occurrence, error_group: group, ingest_event: event, occurred_at: event.occurred_at)
    project.archive!

    described_class.perform_now(preference.id, period_start.iso8601, period_end.iso8601, "daily")

    expect(ActionMailer::Base.deliveries).to be_empty
    expect(EmailNotificationDelivery.count).to eq(0)
  end
end

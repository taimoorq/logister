# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEmailNotificationDispatcher, type: :job do
  before { ActionMailer::Base.deliveries.clear }

  it "sends regression alerts to matching opted-in project recipients" do
    project = create(:project)
    member = create(:user)
    create(:project_membership, project: project, user: member)
    create(:project_notification_preference, project: project, user: member, regression_enabled: false)
    group = create(:error_group, :with_occurrence, project: project, title: "Checkout regressed")

    described_class.call(project: project, kind: "regression", error_group: group, metadata: { "reopen_count" => 1 })

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.first.to).to eq([ project.user.email ])
    delivery = EmailNotificationDelivery.sent.sole
    expect(delivery.notification_kind).to eq("regression")
    expect(delivery.error_group).to eq(group)
  end

  it "uses per-user frequent error thresholds before sending" do
    now = Time.zone.parse("2026-06-20 12:00:00 UTC")
    project = create(:project)
    preference = create(
      :project_notification_preference,
      project: project,
      user: project.user,
      frequent_error_enabled: true,
      frequent_error_threshold_count: 3,
      frequent_error_window_minutes: 10
    )
    group = create(:error_group, project: project, title: "Noisy checkout")
    2.times do |i|
      event = create(:ingest_event, project: project, occurred_at: now - i.minutes)
      create(:error_occurrence, error_group: group, ingest_event: event, occurred_at: event.occurred_at)
    end

    described_class.call(project: project, kind: "frequent_error", error_group: group, metadata: {}, now: now)
    expect(ActionMailer::Base.deliveries).to be_empty

    event = create(:ingest_event, project: project, occurred_at: now)
    create(:error_occurrence, error_group: group, ingest_event: event, occurred_at: event.occurred_at)

    described_class.call(project: project, kind: "frequent_error", error_group: group, metadata: {}, bucket: "2026062012", now: now)

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(EmailNotificationDelivery.sent.sole.user).to eq(preference.user)
  end

  it "routes assignment workflow emails only to the assigned user by default" do
    project = create(:project)
    assignee = create(:user)
    observer = create(:user)
    create(:project_membership, project: project, user: assignee)
    create(:project_membership, project: project, user: observer)
    create(:project_notification_preference, project: project, user: observer, workflow_mode: "assigned_to_me")
    group = create(:error_group, project: project, assignee: assignee)

    described_class.call(
      project: project,
      kind: "assignment",
      error_group: group,
      metadata: { "assigned_user_id" => assignee.id, "actor_user_id" => project.user.id }
    )

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.first.to).to eq([ assignee.email ])
  end

  it "does not count received-only mobile evidence as a real-time project spike" do
    now = Time.zone.parse("2026-06-20 12:00:00 UTC")
    project = create(:project, :android)
    create(
      :project_notification_preference,
      project: project,
      user: project.user,
      project_spike_enabled: true,
      project_spike_threshold_count: 1,
      project_spike_window_minutes: 10
    )
    group = create(:error_group, project: project)
    event = create(:ingest_event, project: project, occurred_at: now)
    create(
      :error_occurrence,
      error_group: group,
      ingest_event: event,
      occurred_at: now,
      dimensions: { "time_precision" => "received_only" }
    )

    described_class.call(project: project, kind: "project_spike", metadata: {}, bucket: "2026062012", now: now)

    expect(ActionMailer::Base.deliveries).to be_empty
    expect(EmailNotificationDelivery.where(notification_kind: "project_spike")).to be_empty
  end

  it "revalidates archived project state before resuming a delivery" do
    delivery = create(:email_notification_delivery, :first_occurrence, status: "pending")
    delivery.project.archive!

    described_class.resume(delivery)

    expect(delivery.reload.status).to eq("skipped")
    expect(delivery.last_error).to eq("project_archived_or_purge_pending")
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "revalidates purge tombstones before resuming a delivery" do
    delivery = create(:email_notification_delivery, :first_occurrence, status: "pending")
    delivery.project.update!(purge_requested_at: Time.current)

    described_class.resume(delivery)

    expect(delivery.reload.status).to eq("skipped")
    expect(delivery.last_error).to eq("project_archived_or_purge_pending")
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end

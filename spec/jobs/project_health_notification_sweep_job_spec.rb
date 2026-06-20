# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectHealthNotificationSweepJob, type: :job do
  before { ActionMailer::Base.deliveries.clear }

  it "sends project spike and performance threshold emails when configured thresholds are crossed" do
    now = Time.zone.parse("2026-06-20 12:00:00 UTC")
    project = create(:project)
    create(
      :project_notification_preference,
      project: project,
      user: project.user,
      project_spike_enabled: true,
      project_spike_threshold_count: 2,
      project_spike_window_minutes: 15,
      performance_alerts_enabled: true,
      performance_p95_threshold_ms: 100
    )
    group = create(:error_group, project: project)
    2.times do |i|
      event = create(:ingest_event, project: project, occurred_at: now - i.minutes)
      create(:error_occurrence, error_group: group, ingest_event: event, occurred_at: event.occurred_at)
    end
    create(:ingest_event, :transaction, project: project, occurred_at: now - 1.minute, context: { "duration_ms" => 250 })

    described_class.perform_now(now.iso8601)

    subjects = ActionMailer::Base.deliveries.map(&:subject)
    expect(subjects).to include(include("Project error spike"), include("Performance threshold"))
    expect(EmailNotificationDelivery.sent.pluck(:notification_kind)).to include("project_spike", "performance_threshold")
  end
end

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

  it "sends typed mobile health alerts once per signal and day when explicitly enabled" do
    now = Time.zone.parse("2026-08-09 12:00:00 UTC")
    project = create(:project, :android)
    create(
      :project_notification_preference,
      project: project,
      user: project.user,
      mobile_health_notifications_enabled: true
    )
    group = create(:error_group, project: project)
    event = create(:ingest_event, project: project, occurred_at: now - 1.hour, created_at: now - 1.hour)
    create(
      :error_occurrence,
      error_group: group,
      ingest_event: event,
      dimensions: { "mapping_status" => "missing" },
      occurred_at: event.occurred_at,
      created_at: event.created_at
    )
    create(
      :project_integration_setting,
      project: project,
      provider: "google_play",
      enabled: true,
      external_project_id: "com.acme.shop",
      credential_reference: "GOOGLE_PLAY_CREDENTIALS",
      last_imported_at: now - 2.days,
      metadata: { "last_error" => { "message" => "permission denied", "at" => (now - 1.hour).iso8601 } }
    )

    2.times { described_class.perform_now(now.iso8601) }

    deliveries = EmailNotificationDelivery.sent.where(project: project)
    expect(deliveries.pluck(:notification_kind)).to contain_exactly("mobile_artifact_health", "mobile_source_health")
    expect(ActionMailer::Base.deliveries.map(&:subject)).to contain_exactly(
      include("Mobile artifact coverage needs attention"),
      include("Mobile reporting source needs attention")
    )
    rendered_bodies = ActionMailer::Base.deliveries.flat_map { |mail| mail.parts.map(&:decoded) }.join
    expect(rendered_bodies).to include("Recovery action", "mapping.txt")
  end
end

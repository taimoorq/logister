# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectErrorMailer, type: :mailer do
  it "adds unsubscribe and SES tagging headers to first occurrence mail" do
    delivery = create(:email_notification_delivery, :first_occurrence)
    create(:project_notification_preference, project: delivery.project, user: delivery.user)

    mail = described_class.first_occurrence(delivery)

    expect(mail.subject).to include("New error")
    expect(mail["List-Unsubscribe"].to_s).to include("/notification_preferences/unsubscribe/")
    expect(mail["List-Unsubscribe-Post"].to_s).to eq("List-Unsubscribe=One-Click")
    expect(mail["X-SES-MESSAGE-TAGS"].to_s).to include("kind=first_occurrence")
    expect(mail.body.encoded).to include(delivery.error_group.title)
  end

  it "labels reporting-interval evidence as newly received instead of newly occurred" do
    delivery = create(:email_notification_delivery, :first_occurrence)
    create(:project_notification_preference, project: delivery.project, user: delivery.user)
    event = delivery.error_group.latest_event_record
    event.update!(
      context: event.context.merge(
        "telemetry_evidence" => {
          "schema_version" => 1,
          "source" => "metrickit",
          "time" => {
            "precision" => "reporting_interval",
            "reporting_start" => 2.days.ago.utc.iso8601(6),
            "reporting_end" => 1.day.ago.utc.iso8601(6),
            "received_at" => Time.current.utc.iso8601(6)
          }
        }
      )
    )

    mail = described_class.first_occurrence(delivery)

    expect(mail.subject).to include("Newly received diagnostic")
    bodies = [ mail.text_part.body.decoded, mail.html_part.body.decoded ]
    expect(bodies).to all(include("does not claim the error first occurred now", "Reporting period", "Received"))
    expect(bodies.join("\n")).not_to include("saw this error type for the first time")
  end

  it "renders group alert mail for regressions" do
    delivery = create(:email_notification_delivery, :regression)
    create(:project_notification_preference, project: delivery.project, user: delivery.user)

    mail = described_class.group_alert(delivery)

    expect(mail.subject).to include("Reopened error")
    expect(mail["X-SES-MESSAGE-TAGS"].to_s).to include("kind=regression")
    expect(mail.body.encoded).to include(delivery.error_group.title)
  end

  it "renders monitor alert mail" do
    monitor = create(:check_in_monitor, :errored)
    delivery = create(
      :email_notification_delivery,
      :monitor_missed,
      project: monitor.project,
      user: monitor.project.user,
      check_in_monitor: monitor
    )
    create(:project_notification_preference, project: delivery.project, user: delivery.user)

    mail = described_class.monitor_alert(delivery)

    expect(mail.subject).to include("Monitor missed")
    expect(mail.body.encoded).to include(monitor.slug)
  end

  it "renders project alert mail" do
    delivery = create(:email_notification_delivery, :retention_failure)
    create(:project_notification_preference, project: delivery.project, user: delivery.user)

    mail = described_class.project_alert(delivery)

    expect(mail.subject).to include("Retention archive failure")
    expect(mail.body.encoded).to include("storage unavailable")
  end
end

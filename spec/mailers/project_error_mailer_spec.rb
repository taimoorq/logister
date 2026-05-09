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
end

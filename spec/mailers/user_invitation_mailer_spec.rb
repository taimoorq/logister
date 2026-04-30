# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserInvitationMailer, type: :mailer do
  let(:code) { "example-invite-code" }
  let(:invitation_id) { "00000000-0000-4000-8000-000000000000" }

  before { ActionMailer::Base.deliveries.clear }

  it "consumes retired invitation jobs without delivering stale mail" do
    expect {
      described_class.invite(
        code: code,
        invitation_id: invitation_id
      ).deliver_now
    }.not_to raise_error

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "is compatible with queued ActionMailer delivery job arguments" do
    expect {
      ActionMailer::MailDeliveryJob.perform_now(
        "UserInvitationMailer",
        "invite",
        "deliver_now",
        args: [
          {
            code: code,
            invitation_id: invitation_id
          }
        ]
      )
    }.not_to raise_error

    expect(ActionMailer::Base.deliveries).to be_empty
  end
end

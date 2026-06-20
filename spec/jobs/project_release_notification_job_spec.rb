# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectReleaseNotificationJob, type: :job do
  before { ActionMailer::Base.deliveries.clear }

  it "sends a release summary to opted-in project recipients" do
    deployment = create(:project_deployment, release: "2026.06.20", repository_full_name: "acme/storefront")
    create(:project_notification_preference, project: deployment.project, user: deployment.project.user, release_notifications_enabled: true)

    described_class.perform_now(deployment.id)

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.first.subject).to include("Release summary")
    expect(ActionMailer::Base.deliveries.first.body.encoded).to include("2026.06.20")
  end
end

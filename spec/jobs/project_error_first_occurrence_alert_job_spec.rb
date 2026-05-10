# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectErrorFirstOccurrenceAlertJob, type: :job do
  before { ActionMailer::Base.deliveries.clear }

  it "emails opted-in project recipients once for a new error group" do
    project = create(:project)
    member = create(:user)
    create(:project_membership, project: project, user: member)
    create(:project_notification_preference, project: project, user: member, first_occurrence_enabled: false)
    group = create(:error_group, :with_occurrence, project: project)

    described_class.perform_now(group.id)
    described_class.perform_now(group.id)

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.first.to).to eq([ project.user.email ])
    expect(EmailNotificationDelivery.sent.count).to eq(1)
    expect(ProjectNotificationPreference.find_by(project: project, user: project.user)).to be_present
  end

  it "does not email for archived projects" do
    project = create(:project)
    group = create(:error_group, :with_occurrence, project: project)
    project.archive!

    described_class.perform_now(group.id)

    expect(ActionMailer::Base.deliveries).to be_empty
    expect(EmailNotificationDelivery.count).to eq(0)
  end
end

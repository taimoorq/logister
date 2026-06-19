# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectSettingsNavigation, type: :model do
  it "shows manager sections and danger for project owners" do
    project = create(:project, user: users(:one))
    navigation = described_class.new(project: project, user: users(:one), requested_section: "integrations")

    expect(navigation.sections.keys).to eq(%w[general notifications team integrations data danger])
    expect(navigation.selected_section).to eq("integrations")
  end

  it "shows manager sections without danger for project admins" do
    project = create(:project, user: users(:one))
    create(:project_membership, project: project, user: users(:two), role: :admin)
    navigation = described_class.new(project: project, user: users(:two), requested_section: "danger")

    expect(navigation.sections.keys).to eq(%w[general notifications team integrations data])
    expect(navigation.selected_section).to eq("general")
  end

  it "shows read-only sections for viewers" do
    project = create(:project, user: users(:one))
    create(:project_membership, project: project, user: users(:two), role: :viewer)
    navigation = described_class.new(project: project, user: users(:two), requested_section: "team")

    expect(navigation.sections.keys).to eq(%w[general notifications])
    expect(navigation.selected_section).to eq("general")
  end

  it "adds app-admin settings without granting owner danger controls" do
    navigation = described_class.new(
      project: projects(:two),
      user: users(:one),
      app_admin: true,
      requested_section: "admin"
    )

    expect(navigation.sections.keys).to eq(%w[general notifications admin])
    expect(navigation.selected_section).to eq("admin")
  end
end

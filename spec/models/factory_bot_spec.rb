# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FactoryBot coverage", type: :model do
  it "builds projects for each supported integration" do
    expect(build(:project, :ruby)).to be_valid
    expect(build(:project, :python)).to be_valid
    expect(build(:project, :javascript)).to be_valid
    expect(build(:project, :cfml)).to be_valid
  end

  it "builds an api key tied to the project owner by default" do
    project = create(:project)
    api_key = create(:api_key, project: project)

    expect(api_key.user).to eq(project.user)
  end

  it "builds the main ingest event variants" do
    expect(build(:ingest_event)).to be_valid
    expect(build(:ingest_event, :metric)).to be_valid
    expect(build(:ingest_event, :transaction)).to be_valid
    expect(build(:ingest_event, :log)).to be_valid
    expect(build(:ingest_event, :check_in)).to be_valid
  end

  it "creates grouped error data" do
    group = create(:error_group, :with_occurrence)

    expect(group).to be_persisted
    expect(group.error_occurrences.count).to eq(1)
    expect(group.latest_event).to be_present
  end

  it "creates a standalone occurrence linked back to its error group" do
    occurrence = create(:error_occurrence)

    expect(occurrence).to be_persisted
    expect(occurrence.ingest_event.error_group).to eq(occurrence.error_group)
  end

  it "creates a check-in monitor with a matching last event" do
    monitor = create(:check_in_monitor, :with_last_event)

    expect(monitor).to be_persisted
    expect(monitor.last_event).to be_check_in
    expect(monitor.last_event.project).to eq(monitor.project)
  end
end

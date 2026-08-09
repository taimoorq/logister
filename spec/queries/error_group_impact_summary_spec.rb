# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorGroupImpactSummary do
  let(:project) { create(:project, :android) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }
  let(:group) { create(:error_group, project: project, occurrence_count: 3) }

  before do
    [
      [ "install-a", "session-a", "1.4.0+42", "Pixel 8", "15", 3.days.ago ],
      [ "install-a", "session-b", "1.4.0+42", "Pixel 8", "15", 2.days.ago ],
      [ "install-b", nil, "1.5.0+43", "Galaxy S24", "14", 1.day.ago ]
    ].each do |installation, session, release, device, os, occurred_at|
      event = create(:ingest_event, project: project, api_key: api_key, occurred_at: occurred_at)
      create(
        :error_occurrence,
        error_group: group,
        ingest_event: event,
        occurred_at: occurred_at,
        release: release,
        installation_hash: installation,
        session_hash: session,
        dimensions: { "device_model" => device, "os_version" => os }
      )
    end
  end

  it "reports distinct impact, completeness, release range, top cohorts, and a trend" do
    summary = described_class.for_group(group)

    expect(summary.events).to eq(3)
    expect(summary.first_seen_at).to be_within(1.second).of(3.days.ago)
    expect(summary.last_seen_at).to be_within(1.second).of(1.day.ago)
    expect(summary.installations).to have_attributes(value: 2, state: :complete, sampled_events: 3, total_events: 3)
    expect(summary.sessions).to have_attributes(value: 2, state: :partial, sampled_events: 2, total_events: 3)
    expect(summary.users).to have_attributes(value: nil, state: :not_collected)
    expect(summary.first_release).to eq("1.4.0+42")
    expect(summary.last_release).to eq("1.5.0+43")
    expect(summary.top_device).to eq(value: "Pixel 8", events: 2)
    expect(summary.top_os).to eq(value: "15", events: 2)
    expect(summary.series.sum { |point| point[:events] }).to eq(3)
  end

  it "honors a caller-provided occurrence scope for every metric" do
    filtered_scope = ErrorOccurrence.where(error_group_id: group.id, release: "1.5.0+43")

    summary = described_class.for_group(group, since: nil, occurrence_scope: filtered_scope)

    expect(summary.events).to eq(1)
    expect(summary.installations).to have_attributes(value: 1, sampled_events: 1, total_events: 1)
    expect(summary.first_release).to eq("1.5.0+43")
    expect(summary.last_release).to eq("1.5.0+43")
    expect(summary.top_device).to eq(value: "Galaxy S24", events: 1)
    expect(summary.series.sum { |point| point[:events] }).to eq(1)
  end

  it "calls a cohort over-indexed only with a material issue share and a sufficient project baseline" do
    hotspot_group = create(:error_group, project: project, occurrence_count: 10)
    baseline_group = create(:error_group, project: project, occurrence_count: 90)
    10.times do |index|
      occurred_at = (index + 1).minutes.ago
      event = create(:ingest_event, project:, api_key:, occurred_at:)
      create(:error_occurrence, error_group: hotspot_group, ingest_event: event, occurred_at:, dimensions: { "device_model" => "Pixel Fold", "os_version" => "16" })
    end
    90.times do |index|
      occurred_at = (index + 1).minutes.ago
      event = create(:ingest_event, project:, api_key:, occurred_at:)
      create(:error_occurrence, error_group: baseline_group, ingest_event: event, occurred_at:, dimensions: { "device_model" => "Galaxy S24", "os_version" => "15" })
    end
    baseline_scope = ErrorOccurrence.joins(:error_group).where(error_groups: { project_id: project.id })

    summary = described_class.for_group(
      hotspot_group,
      since: nil,
      occurrence_scope: baseline_scope.where(error_group_id: hotspot_group.id),
      baseline_scope:
    )

    expect(summary.device_over_index).to have_attributes(
      value: "Pixel Fold",
      issue_events: 10,
      issue_observed_events: 10,
      state: :over_indexed
    )
    expect(summary.device_over_index.issue_share).to eq(1.0)
    expect(summary.device_over_index.baseline_observed_events).to eq(103)
    expect(summary.device_over_index.baseline_share).to be_between(0.09, 0.10)
    expect(summary.device_over_index.lift).to be > 10
    expect(summary.os_over_index).to have_attributes(state: :over_indexed)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectMobileReleaseIndex do
  it "groups Android issue evidence by version, build, and channel using receipt recency" do
    project = create(:project, :android)
    first_group = create(:error_group, project: project)
    second_group = create(:error_group, project: project)
    first = create(:error_occurrence, error_group: first_group, installation_hash: "install-1")
    second = create(:error_occurrence, error_group: second_group, installation_hash: nil)
    dimensions = {
      "app_version" => "4.2.0",
      "build_number" => "310",
      "track" => "production",
      "os_name" => "Android",
      "time_precision" => "exact",
      "evidence_source" => "logister_android",
      "mapping_status" => "mapping_matched"
    }
    first.update_columns(dimensions: dimensions, created_at: 2.hours.ago)
    second.update_columns(dimensions: dimensions, created_at: 5.minutes.ago)

    result = described_class.new(project).call
    release = result.releases.sole

    expect(release.label).to eq("4.2.0 (310)")
    expect(release.channel).to eq("production")
    expect(release.issue_count).to eq(2)
    expect(release.occurrence_count).to eq(2)
    expect(release.affected_installations).to eq(1)
    expect(release.identity_coverage).to eq(:partial)
    expect(release.artifact_state).to eq(:complete)
    expect(release.last_received_at).to be_within(1.second).of(5.minutes.ago)
    expect(release.sources).to eq([ "logister_android" ])
  end

  it "keeps unknown source builds visible instead of assigning the uploader build" do
    project = create(:project, :ios)
    occurrence = create(:error_occurrence, error_group: create(:error_group, project: project))
    occurrence.update!(dimensions: {
      "time_precision" => "reporting_interval",
      "diagnostic_source" => "metrickit",
      "symbolication_status" => "missing"
    })

    release = described_class.new(project).call.releases.sole

    expect(release.label).to eq("Version unknown")
    expect(release.time_precisions).to eq([ "reporting_interval" ])
    expect(release.artifact_state).to eq(:missing)
  end

  it "rejects non-mobile projects rather than fabricating an empty mobile release page" do
    expect do
      described_class.new(build(:project, :ruby))
    end.to raise_error(ArgumentError, /only for Android and iOS/)
  end
end

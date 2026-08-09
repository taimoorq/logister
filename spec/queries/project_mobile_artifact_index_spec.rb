# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectMobileArtifactIndex do
  it "paginates Android inventory and keeps observed-build coverage separate" do
    project = create(:project, :android)
    26.times { create(:android_mapping_file, project:) }
    occurrence = create(:error_occurrence, error_group: create(:error_group, project:))
    occurrence.update!(
      dimensions: { "app_version" => "1.4.0", "build_number" => "42", "track" => "production", "mapping_status" => "missing" }
    )

    first_page = described_class.new(project).call
    second_page = described_class.new(project, page: 2).call

    expect(first_page).to have_attributes(total_artifacts: 26, has_more: true)
    expect(first_page.artifacts.size).to eq(25)
    expect(first_page.status_counts).to eq(verified: 26)
    expect(first_page.observed_builds.sole).to have_attributes(build_number: "42", artifact_state: :missing)
    expect(second_page).to have_attributes(has_more: false)
    expect(second_page.artifacts.size).to eq(1)
  end

  it "preserves distinct iOS verification states without claiming symbolication" do
    project = create(:project, :ios)
    create(:apple_symbol_artifact, project:, status: "verified")
    create(:apple_symbol_artifact, project:, status: "failed")

    result = described_class.new(project).call

    expect(result.status_counts).to eq(failed: 1, verified: 1)
    expect(result.artifacts.map(&:status_label)).to contain_exactly("UUID verified", "Verification failed")
  end
end

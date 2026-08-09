# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackfillErrorOccurrenceDimensionsJob do
  it "upgrades existing mobile dimensions while leaving generic projects outside the mobile contract" do
    mobile_project = create(:project, :android)
    mobile_event = create(
      :ingest_event,
      project: mobile_project,
      context: JSON.parse(Rails.root.join("spec/fixtures/files/android_error_payload.json").read).fetch("context")
    )
    mobile_group = create(:error_group, project: mobile_project)
    mobile_occurrence = create(
      :error_occurrence,
      error_group: mobile_group,
      ingest_event: mobile_event,
      dimensions: { "device_model" => "legacy" }
    )
    generic_project = create(:project)
    generic_event = create(:ingest_event, project: generic_project)
    generic_occurrence = create(
      :error_occurrence,
      error_group: create(:error_group, project: generic_project),
      ingest_event: generic_event,
      dimensions: {}
    )

    described_class.perform_now

    expect(mobile_occurrence.reload.dimensions).to include(
      "materialization_version" => ErrorOccurrenceDimensions::MATERIALIZATION_VERSION.to_s,
      "device_model" => "Pixel 8"
    )
    expect(generic_occurrence.reload.dimensions).to eq({})
  end
end

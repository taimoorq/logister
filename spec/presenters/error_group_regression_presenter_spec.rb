# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorGroupRegressionPresenter do
  it "renders the workflow reason and the proving source clock" do
    proof_at = 2.hours.ago.change(usec: 0)
    group = build(
      :error_group,
      regression_count: 1,
      current_regression: {
        "schema_version" => 1,
        "reason" => "after_resolved",
        "time_precision" => "exact",
        "proof_at" => proof_at.iso8601,
        "received_at" => 5.minutes.ago.iso8601,
        "release" => "1.4.0+42"
      }
    )

    presenter = described_class.new(group)

    expect(presenter.concise_label).to include("after resolution", "occurred")
    expect(presenter.concise_label).not_to include("5 minutes")
    expect(presenter.title).to include("Proving occurrence", "Release 1.4.0+42")
  end

  it "keeps migrated lifetime regressions truthful without inventing a source time" do
    group = build(:error_group, regression_count: 2, current_regression: { "reason" => "legacy_regression", "time_precision" => "unknown" })

    presenter = described_class.new(group)

    expect(presenter).to be_present
    expect(presenter.concise_label).to eq("previously reopened")
  end
end

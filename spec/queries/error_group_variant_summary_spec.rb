# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorGroupVariantSummary do
  let(:project) { create(:project, :android) }
  let(:api_key) { create(:api_key, project:, user: project.user) }
  let(:group) { create(:error_group, project:) }

  def add_occurrence(key:, label:, occurred_at:)
    event = create(:ingest_event, project:, api_key:, occurred_at:)
    dimensions = key ? { "variant_key" => key, "variant_label" => label } : {}
    create(:error_occurrence, error_group: group, ingest_event: event, occurred_at:, dimensions:)
  end

  it "shows variants only when at least two stable raw paths are classified" do
    3.times { |index| add_occurrence(key: "a" * 64, label: "CartStore.write → Disk.flush", occurred_at: (index + 1).hours.ago) }
    2.times { |index| add_occurrence(key: "b" * 64, label: "CartStore.write → Cache.evict", occurred_at: (index + 4).hours.ago) }
    add_occurrence(key: nil, label: nil, occurred_at: 8.hours.ago)

    result = described_class.call(group:)

    expect(result).to have_attributes(total_events: 6, classified_events: 5, coverage: 0.8333)
    expect(result).to be_available
    expect(result.variants.map(&:events)).to eq([ 3, 2 ])
    expect(result.variants.map(&:share)).to eq([ 0.6, 0.4 ])
    expect(result.variants.first.label).to eq("CartStore.write → Disk.flush")
  end

  it "does not call one classified path a set of variants" do
    2.times { |index| add_occurrence(key: "a" * 64, label: "One path", occurred_at: (index + 1).hours.ago) }

    expect(described_class.call(group:)).not_to be_available
  end
end

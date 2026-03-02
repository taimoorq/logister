# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard, type: :model do
  let(:user) { users(:one) }
  let(:project_ids) { user.accessible_projects.pluck(:id) }

  describe ".summary_for" do
    it "returns empty_summary when project_ids blank" do
      expect(described_class.summary_for([])).to eq(Dashboard.empty_summary)
      expect(described_class.summary_for(nil)).to eq(Dashboard.empty_summary)
    end

    it "returns counts and ids for given project_ids" do
      summary = described_class.summary_for(project_ids)
      expect(summary).to include(
        :projects_count,
        :api_keys_count,
        :events_last_24h,
        :recent_event_ids,
        :error_event_ids
      )
      expect(summary[:projects_count]).to be >= 1
      expect(summary[:recent_event_ids]).to be_an(Array)
      expect(summary[:error_event_ids]).to be_an(Array)
    end

    it "limits recent_event_ids to 20" do
      summary = described_class.summary_for(project_ids)
      expect(summary[:recent_event_ids].size).to be <= 20
    end
  end

  describe ".cache_version" do
    it "returns empty array when project_ids blank" do
      expect(described_class.cache_version([])).to eq([])
    end

    it "returns array of two integers for project_ids" do
      version = described_class.cache_version(project_ids)
      expect(version).to be_an(Array)
      expect(version.size).to eq(2)
      expect(version).to all(be_a(Integer))
    end
  end

  describe ".empty_summary" do
    it "returns hash with zero counts and empty arrays" do
      h = described_class.empty_summary
      expect(h[:projects_count]).to eq(0)
      expect(h[:api_keys_count]).to eq(0)
      expect(h[:events_last_24h]).to eq(0)
      expect(h[:recent_event_ids]).to eq([])
      expect(h[:error_event_ids]).to eq([])
    end
  end
end

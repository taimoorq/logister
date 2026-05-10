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
        :active_project_ids_last_24h,
        :events_by_type_last_24h,
        :open_error_groups_count,
        :monitor_status_counts,
        :recent_event_ids,
        :recent_error_group_ids,
        :project_stats
      )
      expect(summary[:projects_count]).to be >= 1
      expect(summary[:events_by_type_last_24h]).to include("error", "log", "metric", "transaction", "check_in")
      expect(summary[:monitor_status_counts]).to include(:ok, :missed, :error)
      expect(summary[:recent_event_ids]).to be_an(Array)
      expect(summary[:project_stats]).to be_a(Hash)
    end

    it "limits recent_event_ids to 20" do
      summary = described_class.summary_for(project_ids)
      expect(summary[:recent_event_ids].size).to be <= 20
    end

    it "returns dashboard-specific project stats without full project index aggregates" do
      project = projects(:one)
      create(:ingest_event, :log, project: project, api_key: api_keys(:one), occurred_at: 30.minutes.ago)

      summary = described_class.summary_for([ project.id ])
      stats = summary[:project_stats].fetch(project.id)

      expect(stats).to include(:open_groups, :activity_events, :latest_event_at)
      expect(stats[:activity_events]).to be >= 1
      expect(stats).not_to include(:total_events, :all_groups, :trend)
    end
  end

  describe ".cache_version" do
    it "returns empty array when project_ids blank" do
      expect(described_class.cache_version([])).to eq([])
    end

    it "returns array of cache version integers for project_ids" do
      version = described_class.cache_version(project_ids)
      expect(version).to be_an(Array)
      expect(version.size).to eq(4)
      expect(version).to all(be_a(Integer))
    end
  end

  describe ".empty_summary" do
    it "returns hash with zero counts and empty arrays" do
      h = described_class.empty_summary
      expect(h[:projects_count]).to eq(0)
      expect(h[:api_keys_count]).to eq(0)
      expect(h[:events_last_24h]).to eq(0)
      expect(h[:open_error_groups_count]).to eq(0)
      expect(h[:monitor_status_counts]).to eq({ ok: 0, missed: 0, error: 0 })
      expect(h[:recent_event_ids]).to eq([])
      expect(h[:recent_error_group_ids]).to eq([])
      expect(h[:project_stats]).to eq({})
    end
  end
end

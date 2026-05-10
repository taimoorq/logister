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
        :assigned_error_groups_count,
        :assigned_error_group_ids,
        :unassigned_error_groups_count,
        :monitor_status_counts,
        :recent_context_event_ids,
        :recent_error_group_ids,
        :project_stats
      )
      expect(summary[:projects_count]).to be >= 1
      expect(summary[:events_by_type_last_24h]).to include("error", "log", "metric", "transaction", "check_in")
      expect(summary[:monitor_status_counts]).to include(:ok, :missed, :error)
      expect(summary[:recent_context_event_ids]).to be_an(Array)
      expect(summary[:project_stats]).to be_a(Hash)
    end

    it "limits recent_context_event_ids to 12" do
      summary = described_class.summary_for(project_ids)
      expect(summary[:recent_context_event_ids].size).to be <= 12
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

    it "returns assignment counts and latest assigned group ids for the viewer" do
      project = projects(:one)
      assigned = create(:error_group, project: project, assignee: user, assigned_by: user, last_seen_at: 5.minutes.ago)
      create(:error_group, project: project, last_seen_at: 10.minutes.ago)
      create(:error_group, :resolved, project: project, assignee: user, assigned_by: user, last_seen_at: 1.minute.ago)

      summary = described_class.summary_for([ project.id ], viewer: user)

      expect(summary[:assigned_error_groups_count]).to eq(1)
      expect(summary[:assigned_error_group_ids]).to eq([ assigned.id ])
      expect(summary[:projects_with_assigned_errors_count]).to eq(1)
      expect(summary[:unassigned_error_groups_count]).to be >= 1
      expect(summary[:projects_with_unassigned_errors_count]).to eq(1)
    end
  end

  describe ".explorer_for" do
    it "returns server-side chart aggregates for the dashboard explorer" do
      travel_to Time.zone.local(2026, 5, 10, 12, 0, 0) do
        project = create(:project)
        api_key = create(:api_key, project: project, user: project.user)
        create(:ingest_event, project: project, api_key: api_key, event_type: :error, context: { "environment" => "production" }, occurred_at: 2.days.ago)
        create(:ingest_event, :log, project: project, api_key: api_key, context: { "environment" => "staging" }, occurred_at: 1.day.ago)
        create(:error_group, project: project, status: :unresolved)

        explorer = described_class.explorer_for([ project.id ])

        expect(explorer[:window_days]).to eq(7)
        expect(explorer[:days]).to eq(%w[2026-05-04 2026-05-05 2026-05-06 2026-05-07 2026-05-08 2026-05-09 2026-05-10])
        expect(explorer[:totals]).to eq(events: 2, active_projects: 1, environments: 2)
        expect(explorer[:timeline]).to include(
          { day: "2026-05-08", event_type: "error", count: 1 },
          { day: "2026-05-09", event_type: "log", count: 1 }
        )
        expect(explorer[:event_types]).to include("error" => 1, "log" => 1, "metric" => 0)
        expect(explorer[:projects]).to contain_exactly(hash_including(project_id: project.id, count: 2, open_errors: 1))
        expect(explorer[:environments]).to contain_exactly({ name: "production", count: 1 }, { name: "staging", count: 1 })
      end
    end

    it "applies event type, project, and environment filters before aggregating" do
      project = create(:project)
      other_project = create(:project, user: project.user)
      api_key = create(:api_key, project: project, user: project.user)
      other_api_key = create(:api_key, project: other_project, user: other_project.user)
      create(:ingest_event, project: project, api_key: api_key, event_type: :error, context: { "environment" => "production" })
      create(:ingest_event, :log, project: project, api_key: api_key, context: { "environment" => "staging" })
      create(:ingest_event, :log, project: other_project, api_key: other_api_key, context: { "environment" => "production" })

      explorer = described_class.explorer_for(
        [ project.id, other_project.id ],
        event_type: "log",
        project_id: project.id,
        environment: "staging"
      )

      expect(explorer[:totals]).to eq(events: 1, active_projects: 1, environments: 1)
      expect(explorer[:event_types]).to include("error" => 0, "log" => 1)
      expect(explorer[:projects]).to contain_exactly(hash_including(project_id: project.id, count: 1))
      expect(explorer[:environments]).to eq([ { name: "staging", count: 1 } ])
    end
  end

  describe ".empty_summary" do
    it "returns hash with zero counts and empty arrays" do
      h = described_class.empty_summary
      expect(h[:projects_count]).to eq(0)
      expect(h[:api_keys_count]).to eq(0)
      expect(h[:events_last_24h]).to eq(0)
      expect(h[:open_error_groups_count]).to eq(0)
      expect(h[:assigned_error_groups_count]).to eq(0)
      expect(h[:assigned_error_group_ids]).to eq([])
      expect(h[:unassigned_error_groups_count]).to eq(0)
      expect(h[:monitor_status_counts]).to eq({ ok: 0, missed: 0, error: 0 })
      expect(h[:recent_context_event_ids]).to eq([])
      expect(h[:recent_error_group_ids]).to eq([])
      expect(h[:project_stats]).to eq({})
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard ClickHouse event rollup", type: :model do
  it "uses the analytics rollup for all-project activity signals" do
    project = projects(:one)
    latest_event_at = Time.current.change(usec: 0)
    rollup = {
      event_type_counts: Dashboard::EVENT_TYPE_ORDER.index_with { 0 }.merge("metric" => 7),
      active_project_ids: [ project.id ],
      activity_event_counts: { project.id => 7 },
      latest_event_at_by_project: { project.id => latest_event_at }
    }
    allow(Logister::ClickhouseEventRollup).to receive(:call).and_return(rollup)

    summary = Dashboard.summary_for(
      [ project.id ],
      include_assignments: false,
      include_context_events: false,
      include_project_signals: true,
      include_project_stats: true
    )

    expect(summary[:events_last_24h]).to eq(7)
    expect(summary[:active_project_ids_last_24h]).to eq([ project.id ])
    expect(summary.dig(:project_stats, project.id, :activity_events)).to eq(7)
    expect(summary.dig(:project_stats, project.id, :latest_event_at)).to eq(latest_event_at)
    expect(Logister::ClickhouseEventRollup).to have_received(:call).once
  end

  it "uses ClickHouse explorer aggregates and adds PostgreSQL error state" do
    project = projects(:one)
    create(:error_group, project:, status: :unresolved)
    clickhouse_payload = {
      totals: { events: 9, active_projects: 1, environments: 1 },
      timeline: [ { day: Time.current.to_date.iso8601, event_type: "metric", count: 9 } ],
      event_types: Dashboard::EVENT_TYPE_ORDER.index_with { 0 }.merge("metric" => 9),
      projects: [ { project_id: project.id, count: 9 } ],
      environments: [ { name: "production", count: 9 } ]
    }
    allow(Logister::ClickhouseExplorer).to receive(:call).and_return(clickhouse_payload)

    explorer = Dashboard.explorer_for([ project.id ])

    expect(explorer[:totals]).to eq(events: 9, active_projects: 1, environments: 1)
    expect(explorer[:projects]).to contain_exactly(
      project_id: project.id,
      count: 9,
      open_errors: be >= 1
    )
    expect(Logister::ClickhouseExplorer).to have_received(:call).once
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::SelfMonitoringPolicy, type: :model do
  let(:project) { create(:project, :ruby) }
  let(:installation) { Installation.current }

  before do
    installation.update!(self_monitoring_project: project)
  end

  it "allows normal local telemetry through the standard downstream paths" do
    event = build(:ingest_event, project: project, context: { "environment" => "production" })
    policy = described_class.new(project: project, event: event, installation: installation)

    expect(policy).to be_local_self_monitoring
    expect(policy).to be_mirror_to_clickhouse
    expect(policy).to be_send_notifications
    expect(policy).to be_update_check_in_monitor
  end

  it "does not send a ClickHouse-origin diagnostic back to ClickHouse" do
    event = build(:ingest_event, project: project, context: {
      "logister_internal" => { "component" => "clickhouse", "feedback_depth" => 1 }
    })
    policy = described_class.new(project: project, event: event, installation: installation)

    expect(policy).not_to be_mirror_to_clickhouse
    expect(policy).to be_send_notifications
  end

  it "does not notify about failures produced by the notification subsystem" do
    event = build(:ingest_event, project: project, context: {
      "logister_internal" => { "component" => "notifications", "feedback_depth" => 1 }
    })
    policy = described_class.new(project: project, event: event, installation: installation)

    expect(policy).to be_mirror_to_clickhouse
    expect(policy).not_to be_send_notifications
    expect(policy).not_to be_index_deployment
    expect(policy).not_to be_update_check_in_monitor
  end

  it "stops all downstream fan-out beyond the feedback budget" do
    event = build(:ingest_event, project: project, context: {
      "logister_internal" => { "component" => "notifications", "feedback_depth" => 2 }
    })
    policy = described_class.new(project: project, event: event, installation: installation)

    expect(policy).not_to be_mirror_to_clickhouse
    expect(policy).not_to be_send_notifications
    expect(policy).not_to be_index_deployment
    expect(policy).not_to be_update_check_in_monitor
  end

  it "does not change routing for ordinary or remotely monitored projects" do
    other_project = create(:project, :ruby)
    event = build(:ingest_event, project: other_project, context: {
      "logister_internal" => { "component" => "clickhouse", "feedback_depth" => 5 }
    })
    policy = described_class.new(project: other_project, event: event, installation: installation)

    expect(policy).not_to be_local_self_monitoring
    expect(policy).to be_mirror_to_clickhouse
    expect(policy).to be_send_notifications
  end
end

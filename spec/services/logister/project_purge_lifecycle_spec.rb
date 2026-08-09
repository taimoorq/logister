# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project purge lifecycle", type: :model do
  include ActiveJob::TestHelper

  class PurgeAdapterResult
    def initialize(result, calls, name, &block)
      @result = result
      @calls = calls
      @name = name
      @block = block
    end

    def call
      @calls << @name
      @block&.call
      @result
    end
  end

  before { clear_enqueued_jobs }

  it "rejects direct project destruction without a durable purge ledger" do
    project = create(:project)

    expect(project.destroy).to be(false)
    expect(project.errors.full_messages).to include("Must be deleted through the audited project purge lifecycle")
    expect(Project.exists?(project.id)).to be(true)
  end

  it "tombstones once, revokes credentials, and creates an ordered durable ledger" do
    project = create(:project)
    api_key = create(:api_key, project: project, user: project.user)

    first = Logister::ProjectPurgeRequest.new(project: project, requested_by: project.user, enqueue: false).call
    second = Logister::ProjectPurgeRequest.new(project: project.reload, requested_by: project.user, enqueue: false).call

    expect(second.id).to eq(first.id)
    expect(ProjectPurge.where(project_uuid: project.uuid).count).to eq(1)
    expect(project.reload).to be_purge_pending
    expect(project).to be_archived
    expect(api_key.reload.revoked_at).to be_present
    expect(first.steps.order(:position).pluck(:store_name)).to eq(%w[archives clickhouse postgresql redis])
    expect(first.audit_log.pluck("event")).to include("requested", "tombstoned")
  end

  it "runs Redis last and records verified terminal states after the project row is gone" do
    project = create(:project)
    purge = Logister::ProjectPurgeRequest.new(project: project, requested_by: project.user, enqueue: false).call
    calls = []
    adapters = {
      "archives" => PurgeAdapterResult.new({ status: "completed" }, calls, "archives"),
      "clickhouse" => PurgeAdapterResult.new({ status: "completed" }, calls, "clickhouse"),
      "postgresql" => PurgeAdapterResult.new({ status: "completed" }, calls, "postgresql") { project.destroy_for_purge! },
      "redis" => PurgeAdapterResult.new({ status: "completed", verified_absent: true }, calls, "redis")
    }

    result = Logister::ProjectPurgeRunner.new(project_purge: purge, adapters: adapters).call

    expect(result.fetch(:status)).to eq("completed")
    expect(calls).to eq(%w[archives clickhouse postgresql redis])
    expect(purge.reload.project).to be_nil
    expect(purge.steps.pluck(:status)).to all(eq("completed"))
    expect(purge.audit_log.last.fetch("event")).to eq("completed")
  end

  it "stops visibly at an external gate and permits the requesting owner to resume" do
    project = create(:project)
    owner = project.user
    purge = Logister::ProjectPurgeRequest.new(project: project, requested_by: owner, enqueue: false).call
    calls = []
    adapters = {
      "archives" => PurgeAdapterResult.new({ status: "completed" }, calls, "archives"),
      "clickhouse" => PurgeAdapterResult.new(
        { status: "awaiting_external", rollout_gate: "LOGISTER_ENABLE_PROJECT_PURGE_CLICKHOUSE" },
        calls,
        "clickhouse"
      ),
      "postgresql" => PurgeAdapterResult.new({ status: "completed" }, calls, "postgresql") { project.destroy_for_purge! },
      "redis" => PurgeAdapterResult.new({ status: "completed" }, calls, "redis")
    }

    result = Logister::ProjectPurgeRunner.new(project_purge: purge, adapters: adapters).call

    expect(result).to include(status: "awaiting_external", current_step: "clickhouse")
    expect(calls).to eq(%w[archives clickhouse])
    expect(purge.reload.status).to eq("awaiting_external")
    expect(purge.project).to eq(project)
    expect(Project.exists?(project.id)).to be(true)
    expect(purge.steps.find_by!(store_name: "postgresql").status).to eq("pending")
    expect(purge.steps.find_by!(store_name: "redis").status).to eq("pending")

    allow(ProjectPurgeJob).to receive(:perform_later)
    Logister::ProjectPurgeResume.new(project_purge: purge, actor: owner).call

    expect(ProjectPurgeJob).to have_received(:perform_later).with(purge.id)
    expect(purge.reload.status).to eq("tombstoned")
    expect(purge.audit_log.last.fetch("event")).to eq("resume_requested")
  end

  it "removes PostgreSQL telemetry before destroying the project while retaining the purge audit" do
    project = create(:project)
    create(:ingest_event, :log, project: project, occurred_at: 2.days.ago)
    create(:trace_span, project: project, started_at: 2.days.ago)
    create(:error_group, :with_occurrence, project: project)
    purge = Logister::ProjectPurgeRequest.new(project: project, requested_by: project.user, enqueue: false).call

    result = Logister::ProjectPurgeAdapters::Postgresql.new(project_purge: purge).call

    expect(result).to include(status: "completed", project_deleted: true, verified_project_absent: true)
    expect(result.dig(:source_counts, "ingest_events")).to be >= 2
    expect(Project.exists?(project.id)).to be(false)
    expect(purge.reload.project).to be_nil
    expect(purge.project_uuid).to eq(project.uuid)
  end
end

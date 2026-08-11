# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectRetentionJob, type: :job do
  include ActiveJob::TestHelper

  before { clear_enqueued_jobs }

  it "runs durable archive lifecycle work on the isolated archive queue" do
    expect(described_class.queue_name).to eq("archives")
  end

  it "keeps the legacy project/dry-run payload compatible by adopting a durable run" do
    project = projects(:one)
    run = create(:project_retention_run, project: project, dry_run: true, trigger_kind: "legacy")
    coordinator_result = Logister::ProjectRetentionRunCoordinator::Result.new(run: run, created: false)
    runner = instance_double(
      Logister::ProjectRetentionRunRunner,
      call: { action: :complete, status: "completed", result: { deleted: { hot_events: 0 } } }
    )
    allow(Logister::ProjectRetentionRunCoordinator).to receive(:create_or_find!).and_return(coordinator_result)
    allow(Logister::ProjectRetentionRunRunner).to receive(:new).with(run: run).and_return(runner)

    described_class.perform_now(project.id, dry_run: true)

    expect(Logister::ProjectRetentionRunCoordinator).to have_received(:create_or_find!).with(
      project: project,
      scheduled_for: kind_of(Time),
      dry_run: true,
      trigger_kind: "legacy"
    )
    expect(runner).to have_received(:call)
  end

  it "schedules a durable continuation with the same run identity" do
    run = create(:project_retention_run)
    runner = instance_double(
      Logister::ProjectRetentionRunRunner,
      call: { action: :continue, status: "queued", wait: 1.second }
    )
    allow(Logister::ProjectRetentionRunRunner).to receive(:new).with(run: run).and_return(runner)

    expect {
      described_class.perform_now(run.project_id, dry_run: false, run_id: run.id)
    }.to have_enqueued_job(described_class).with(
      run.project_id,
      dry_run: false,
      run_id: run.id
    )
  end

  it "rejects a serialized run that belongs to another project" do
    run = create(:project_retention_run)
    other_project = create(:project)

    expect {
      described_class.perform_now(other_project.id, dry_run: false, run_id: run.id)
    }.to raise_error(ArgumentError, /does not match/)
  end
end

RSpec.describe ProjectRetentionSweepJob, type: :job do
  include ActiveJob::TestHelper

  before { clear_enqueued_jobs }

  it "creates and queues one durable run for every project, including archived projects" do
    archived_project = create(:project, :archived)
    project_ids = Project.order(:id).pluck(:id)

    expect {
      described_class.perform_now(dry_run: true)
    }.to change(ProjectRetentionRun, :count).by(Project.count)

    enqueued = enqueued_jobs.select { |job| job.fetch(:job) == ProjectRetentionJob }
    enqueued_project_ids = enqueued.map { |job| job.fetch(:args).first }
    expect(enqueued_project_ids).to contain_exactly(*project_ids)
    expect(enqueued_project_ids).to include(archived_project.id)
    expect(ProjectRetentionRun.pluck(:dry_run)).to all(be(true))
  end

  it "does not duplicate work when an active non-dry-run already exists" do
    project = projects(:one)
    active = create(:project_retention_run, project: project)

    described_class.perform_now(dry_run: false)

    expect(project.retention_runs.active).to contain_exactly(active)
    matching_jobs = enqueued_jobs.select do |job|
      job.fetch(:job) == ProjectRetentionJob && job.fetch(:args).first == project.id
    end
    expect(matching_jobs).to be_empty
  end
end

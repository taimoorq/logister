# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectRetentionJob, type: :job do
  it "runs project retention with the requested dry-run mode" do
    project = projects(:one)
    runner = instance_double(Logister::ProjectRetentionRunner, call: { deleted: { hot_events: 0 } })

    allow(Logister::ProjectRetentionRunner).to receive(:new).and_return(runner)

    described_class.perform_now(project.id, dry_run: true)

    expect(Logister::ProjectRetentionRunner).to have_received(:new).with(project: project, dry_run: true)
    expect(runner).to have_received(:call)
  end

  it "skips retention when another non-dry-run job holds the project lock" do
    project = projects(:one)
    lock = instance_double(Logister::ProjectRetentionLock, acquire: false, release: true)

    allow(Logister::ProjectRetentionLock).to receive(:new).and_return(lock)
    allow(Logister::ProjectRetentionRunner).to receive(:new)

    described_class.perform_now(project.id, dry_run: false)

    expect(Logister::ProjectRetentionRunner).not_to have_received(:new)
    expect(lock).not_to have_received(:release)
  end

  it "releases the project lock after running retention" do
    project = projects(:one)
    lock = instance_double(Logister::ProjectRetentionLock, acquire: true, release: true)
    runner = instance_double(Logister::ProjectRetentionRunner, call: { deleted: { hot_events: 0 } })

    allow(Logister::ProjectRetentionLock).to receive(:new).and_return(lock)
    allow(Logister::ProjectRetentionRunner).to receive(:new).and_return(runner)

    described_class.perform_now(project.id, dry_run: false)

    expect(lock).to have_received(:release)
  end
end

RSpec.describe ProjectRetentionSweepJob, type: :job do
  it "queues retention for every project, including archived projects" do
    archived_project = create(:project, :archived)

    allow(ProjectRetentionJob).to receive(:perform_later)

    described_class.perform_now(dry_run: true)

    expect(ProjectRetentionJob).to have_received(:perform_later).exactly(Project.count).times
    expect(ProjectRetentionJob).to have_received(:perform_later).with(projects(:one).id, dry_run: true)
    expect(ProjectRetentionJob).to have_received(:perform_later).with(archived_project.id, dry_run: true)
  end
end

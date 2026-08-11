# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "logister:telemetry:retention" do
  include ActiveJob::TestHelper

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("logister:telemetry:retention")
  end

  let(:task) { Rake::Task["logister:telemetry:retention"] }

  before do
    @original_environment = {
      "DRY_RUN" => ENV["DRY_RUN"],
      "CONFIRM" => ENV["CONFIRM"]
    }
    clear_enqueued_jobs
    task.reenable
  end

  after do
    @original_environment.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  it "enqueues confirmed deletion through the durable run ledger" do
    project = create(:project)
    create(:project_retention_policy, project: project)
    ENV["DRY_RUN"] = "false"
    ENV["CONFIRM"] = "retention"

    expect { task.invoke(project.uuid) }.to have_enqueued_job(ProjectRetentionJob)

    run = project.retention_runs.sole
    expect(run).to have_attributes(status: "queued", trigger_kind: "manual", dry_run: false)
    expect(enqueued_jobs.last.fetch(:args).last).to include("run_id" => run.id)
  end
end

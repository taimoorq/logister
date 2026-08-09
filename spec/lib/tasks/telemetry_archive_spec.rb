# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "logister:telemetry:archive" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("logister:telemetry:archive")
  end

  let(:task) { Rake::Task["logister:telemetry:archive"] }

  before { task.reenable }

  it "refuses untracked global archive uploads" do
    expect { task.invoke("ingest_events", "30") }
      .to raise_error(SystemExit, /PROJECT_UUID is required/)
  end
end

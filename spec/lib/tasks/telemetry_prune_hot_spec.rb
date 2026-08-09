# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "logister:telemetry:prune_hot" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("logister:telemetry:prune_hot")
  end

  let(:task) { Rake::Task["logister:telemetry:prune_hot"] }

  before { task.reenable }

  it "refuses the legacy global destructive bypass" do
    expect { task.invoke }.to raise_error(SystemExit, /global delete cannot honor project archive policy/)
  end
end

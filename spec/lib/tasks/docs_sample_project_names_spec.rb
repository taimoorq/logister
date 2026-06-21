# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "logister:docs:sample_project_names" do
  fixtures :all

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("logister:docs:sample_project_names")
  end

  around do |example|
    previous_env = {
      "DRY_RUN" => ENV["DRY_RUN"],
      "SEED" => ENV["SEED"],
      "CONFIRM" => ENV["CONFIRM"]
    }

    example.run
  ensure
    previous_env.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    task.reenable
  end

  let(:task) { Rake::Task["logister:docs:sample_project_names"] }

  it "replaces project names and slugs with Faker sample data" do
    original_name = projects(:one).name
    original_slug = projects(:one).slug

    ENV["SEED"] = "1234"

    expect { task.invoke }.to output(/"projects_changed": #{Project.count}/).to_stdout

    projects(:one).reload
    expect(projects(:one).name).not_to eq(original_name)
    expect(projects(:one).slug).not_to eq(original_slug)
    expect(projects(:one).slug).to eq(projects(:one).name.parameterize)
  end

  it "keeps generated slugs unique for each project owner" do
    require "faker"

    allow(Faker::App).to receive(:name).and_return("Acme")

    expect { task.invoke }.to output.to_stdout

    slugs = Project.where(user: users(:one)).pluck(:slug)
    expect(slugs).to contain_exactly("acme-rails", "acme-rails-2")
  end

  it "does not persist changes during a dry run" do
    original_projects = Project.order(:id).pluck(:id, :name, :slug)

    ENV["DRY_RUN"] = "true"
    ENV["SEED"] = "1234"

    expect { task.invoke }.to output(/"dry_run": true/).to_stdout

    expect(Project.order(:id).pluck(:id, :name, :slug)).to eq(original_projects)
  end
end

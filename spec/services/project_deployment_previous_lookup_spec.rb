# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectDeploymentPreviousLookup do
  let(:project) { create(:project) }

  def deployment(**attributes)
    create(:project_deployment, project:, project_source_repository: nil, repository_full_name: "acme/app", **attributes)
  end

  it "keeps repository, environment, project and strict-earlier time boundaries" do
    time = Time.current.change(usec: 123456)
    previous = deployment(deployed_at: time - 1.hour)
    tied = deployment(deployed_at: time - 1.hour)
    current = deployment(deployed_at: time)
    deployment(deployed_at: time)
    staging = deployment(environment: "staging", deployed_at: time - 1.minute)
    repository = deployment(repository_full_name: "acme/other", deployed_at: time - 1.minute)
    foreign = create(:project_deployment, deployed_at: time - 1.second)

    result = described_class.call(project:, deployments: [ current, previous, staging, repository, foreign ])

    expect(result.keys).to eq([ current.id ])
    expect(result[current.id]).to eq(tied)
  end

  it "preserves updated_at ordering for deployments without deployed_at" do
    time = Time.current
    current = deployment(deployed_at: time)
    previous = deployment(deployed_at: time - 1.hour)
    fallback = deployment(deployed_at: nil, created_at: time - 2.hours, updated_at: time - 1.minute)

    expect(described_class.call(project:, deployments: [ current ]).fetch(current.id)).to eq(fallback)
    expect(described_class.call(project:, deployments: [ previous ]).fetch(previous.id)).to eq(fallback)
  end

  it "materializes at most one predecessor for each visible deployment in a long history" do
    time = Time.current
    previous = deployment(deployed_at: time - 1.minute)
    current = deployment(deployed_at: time)
    rows = 300.times.map do |index|
      previous.attributes.except("id", "uuid").merge("release" => "history-#{index}", "deployed_at" => time - (index + 2).minutes)
    end
    ProjectDeployment.insert_all!(rows)
    materialized = 0
    callback = ->(*, payload) { materialized += payload[:record_count] if payload[:class_name] == "ProjectDeployment" }

    ActiveSupport::Notifications.subscribed(callback, "instantiation.active_record") do
      expect(described_class.call(project:, deployments: [ current ]).fetch(current.id)).to eq(previous)
    end
    expect(materialized).to eq(1)
  end
end

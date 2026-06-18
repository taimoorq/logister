# frozen_string_literal: true

FactoryBot.define do
  factory :project_deployment do
    association :project
    project_source_repository { association(:project_source_repository, project: project) }
    provider { "github" }
    repository_full_name { project_source_repository&.full_name || "acme/storefront" }
    environment { "production" }
    sequence(:release) { |n| "2026.06.#{n}" }
    commit_sha { "abc1234" }
    branch { "main" }
    deployed_at { Time.current }
    source { "api" }
    metadata { {} }
  end
end

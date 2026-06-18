# frozen_string_literal: true

FactoryBot.define do
  factory :project_source_repository do
    association :project
    association :github_installation
    provider { "github" }
    sequence(:external_id) { |n| 20_000 + n }
    sequence(:full_name) { |n| "acme/service-#{n}" }
    default_branch { "main" }
    runtime_root { "/app" }
    source_root { nil }
    enabled { true }
    metadata { {} }
  end
end

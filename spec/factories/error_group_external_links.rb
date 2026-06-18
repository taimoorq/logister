# frozen_string_literal: true

FactoryBot.define do
  factory :error_group_external_link do
    project
    error_group { association(:error_group, project: project) }
    association :created_by, factory: :user
    provider { "github" }
    link_type { "issue" }
    sequence(:url) { |n| "https://github.com/acme/storefront/issues/#{n}" }
    title { nil }
    repository_full_name { nil }
    external_id { nil }
    metadata { {} }
  end
end

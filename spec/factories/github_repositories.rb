# frozen_string_literal: true

FactoryBot.define do
  factory :github_repository do
    association :github_installation
    sequence(:external_id) { |n| 30_000 + n }
    sequence(:full_name) { |n| "acme/synced-#{n}" }
    default_branch { "main" }
    html_url { "https://github.com/#{full_name}" }
    private { true }
    archived { false }
    active { true }
    permissions { { "contents" => "read", "metadata" => "read" } }
    metadata { {} }
    last_synced_at { Time.current }
  end
end

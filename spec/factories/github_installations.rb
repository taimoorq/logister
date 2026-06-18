# frozen_string_literal: true

FactoryBot.define do
  factory :github_installation do
    sequence(:installation_id) { |n| 10_000 + n }
    account_login { "acme" }
    account_type { "Organization" }
    repository_selection { "selected" }
    active { true }
    permissions { { "contents" => "read", "metadata" => "read" } }
    events { [] }
  end
end

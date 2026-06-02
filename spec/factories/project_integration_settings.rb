# frozen_string_literal: true

FactoryBot.define do
  factory :project_integration_setting do
    association :project, factory: [ :project, :cloudflare_pages ]
    provider { "cloudflare_pages" }
    enabled { false }
    account_id { "account-123" }
    external_project_name { "marketing-site" }
    external_project_id { nil }
    credential_reference { "CLOUDFLARE_API_TOKEN" }
    metadata { {} }
  end
end

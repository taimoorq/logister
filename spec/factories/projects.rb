# frozen_string_literal: true

FactoryBot.define do
  factory :project do
    association :user
    sequence(:name) { |n| "Project #{n}" }
    sequence(:slug) { |n| "project-#{n}" }
    description { nil }
    integration_kind { "ruby" }

    trait :ruby do
      integration_kind { "ruby" }
    end

    trait :python do
      integration_kind { "python" }
    end

    trait :dotnet do
      integration_kind { "dotnet" }
    end

    trait :cloudflare_pages do
      integration_kind { "cloudflare_pages" }
    end

    trait :android do
      integration_kind { "android" }
    end

    trait :ios do
      integration_kind { "ios" }
    end

    trait :javascript do
      integration_kind { "javascript" }
    end

    trait :cfml do
      integration_kind { "cfml" }
    end

    trait :http_api do
      integration_kind { "http_api" }
    end

    trait :archived do
      archived_at { Time.current }
    end
  end
end

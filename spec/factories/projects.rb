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

    trait :javascript do
      integration_kind { "javascript" }
    end

    trait :cfml do
      integration_kind { "cfml" }
    end
  end
end

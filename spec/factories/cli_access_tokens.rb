# frozen_string_literal: true

FactoryBot.define do
  factory :cli_access_token do
    association :user
    sequence(:name) { |n| "CLI token #{n}" }
    scopes { CliAccessToken::READ_SCOPES }
    allowed_project_ids { [] }
    all_projects { true }
    expires_at { 30.days.from_now }

    trait :project_limited do
      transient do
        project { nil }
      end

      all_projects { false }
      allowed_project_ids { [] }

      after(:build) do |token, evaluator|
        project = evaluator.project || build(:project, user: token.user)
        project.save! unless project.persisted?
        token.allowed_project_ids = [ project.id ]
      end
    end

    trait :expired do
      expires_at { 1.minute.ago }
    end

    trait :revoked do
      revoked_at { Time.current }
    end
  end
end

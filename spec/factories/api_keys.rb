# frozen_string_literal: true

FactoryBot.define do
  factory :api_key do
    association :project
    user { project.user }
    sequence(:name) { |n| "Key #{n}" }
    # token_digest and plain_token are set by the model on create

    trait :revoked do
      revoked_at { Time.current }
    end
  end
end

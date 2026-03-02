# frozen_string_literal: true

FactoryBot.define do
  factory :api_key do
    association :user
    association :project
    sequence(:name) { |n| "Key #{n}" }
    # token_digest and plain_token are set by the model on create
  end
end

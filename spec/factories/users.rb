# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    confirmed_at { Time.current }
    name { nil }

    trait :unconfirmed do
      confirmed_at { nil }
      confirmation_token { "token-#{SecureRandom.hex(8)}" }
      confirmation_sent_at { Time.current }
    end
  end
end

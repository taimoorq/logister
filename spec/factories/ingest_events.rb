# frozen_string_literal: true

FactoryBot.define do
  factory :ingest_event do
    association :project
    association :api_key
    event_type { :error }
    level { "error" }
    sequence(:message) { |n| "Error message #{n}" }
    fingerprint { nil }
    context { {} }
    occurred_at { Time.current }

    trait :metric do
      event_type { :metric }
      level { "info" }
      message { "db.query" }
      context { { "duration_ms" => 42.5, "name" => "User Load" } }
    end
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :ingest_event do
    association :project
    api_key { association :api_key, project: project, user: project.user }
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

    trait :transaction do
      event_type { :transaction }
      level { "info" }
      sequence(:message) { |n| "transaction.#{n}" }
      context { { "transaction_name" => "CheckoutController#create", "duration_ms" => 180.5, "status" => 200 } }
    end

    trait :log do
      event_type { :log }
      level { "info" }
      sequence(:message) { |n| "Log message #{n}" }
    end

    trait :check_in do
      event_type { :check_in }
      level { "info" }
      sequence(:message) { |n| "heartbeat-#{n}" }
      context do
        {
          "check_in_slug" => message,
          "check_in_status" => "ok",
          "expected_interval_seconds" => 300,
          "environment" => "production"
        }
      end
    end

    trait :python do
      project { association :project, :python }
      api_key { association :api_key, project: project, user: project.user }
    end

    trait :dotnet do
      project { association :project, :dotnet }
      api_key { association :api_key, project: project, user: project.user }
    end

    trait :javascript do
      project { association :project, :javascript }
      api_key { association :api_key, project: project, user: project.user }
    end

    trait :cfml do
      project { association :project, :cfml }
      api_key { association :api_key, project: project, user: project.user }
    end

    trait :grouped do
      after(:create) do |event|
        ErrorGroupingService.call(event) if event.error?
      end
    end
  end
end

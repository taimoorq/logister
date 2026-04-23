# frozen_string_literal: true

FactoryBot.define do
  factory :check_in_monitor do
    association :project
    sequence(:slug) { |n| "monitor-#{n}" }
    environment { "production" }
    expected_interval_seconds { 300 }
    last_check_in_at { Time.current }
    last_status { "ok" }
    consecutive_missed_count { 0 }
    last_error_at { nil }
    last_event { nil }

    transient do
      api_key { nil }
    end

    trait :with_last_event do
      last_event do
        association :ingest_event,
                    :check_in,
                    project: project,
                    api_key: (api_key || association(:api_key, project: project, user: project.user)),
                    message: slug,
                    occurred_at: last_check_in_at,
                    context: {
                      "check_in_slug" => slug,
                      "check_in_status" => last_status,
                      "expected_interval_seconds" => expected_interval_seconds,
                      "environment" => environment
                    }
      end
    end

    trait :errored do
      last_status { "error" }
      last_error_at { Time.current }
    end

    trait :missed do
      expected_interval_seconds { 60 }
      last_check_in_at { 10.minutes.ago }
      last_status { "ok" }
    end
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :notification_intent do
    association :project
    error_group { association(:error_group, project: project) }
    check_in_monitor { nil }
    kind { "first_occurrence" }
    sequence(:dedup_key) { |n| "notification-intent-#{n}" }
    status { "pending" }
    available_at { Time.current }
    metadata { {} }

    trait :monitor_recovered do
      error_group { nil }
      check_in_monitor { association(:check_in_monitor, project: project) }
      kind { "monitor_recovered" }
      metadata do
        {
          "transition_id" => check_in_monitor.notification_transition_id || SecureRandom.uuid,
          "expected_status" => "ok"
        }
      end
    end
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :error_group do
    association :project
    sequence(:fingerprint) { |n| "error-group-#{n}" }
    sequence(:title) { |n| "Error group #{n}" }
    subtitle { nil }
    stage { "production" }
    severity { "error" }
    status { :unresolved }
    first_seen_at { 1.hour.ago }
    last_seen_at { 5.minutes.ago }
    occurrence_count { 0 }
    latest_event { nil }

    transient do
      api_key { nil }
    end

    trait :with_latest_event do
      latest_event do
        association :ingest_event,
                    project: project,
                    api_key: (api_key || association(:api_key, project: project, user: project.user)),
                    fingerprint: fingerprint,
                    message: title,
                    occurred_at: last_seen_at
      end
    end

    trait :with_occurrence do
      with_latest_event

      after(:create) do |group, evaluator|
        event = group.latest_event || create(
          :ingest_event,
          project: group.project,
          api_key: (evaluator.api_key || create(:api_key, project: group.project, user: group.project.user)),
          fingerprint: group.fingerprint,
          message: group.title,
          occurred_at: group.last_seen_at
        )

        create(:error_occurrence, error_group: group, ingest_event: event, occurred_at: event.occurred_at)
        group.update!(
          latest_event: event,
          first_seen_at: [ group.first_seen_at, event.occurred_at ].compact.min,
          last_seen_at: [ group.last_seen_at, event.occurred_at ].compact.max,
          occurrence_count: group.error_occurrences.count
        )
      end
    end

    trait :resolved do
      status { :resolved }
      resolved_at { Time.current }
    end

    trait :ignored do
      status { :ignored }
      ignored_at { Time.current }
    end

    trait :archived do
      status { :archived }
      archived_at { Time.current }
    end
  end
end

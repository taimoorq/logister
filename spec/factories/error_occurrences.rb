# frozen_string_literal: true

FactoryBot.define do
  factory :error_occurrence do
    transient do
      api_key { nil }
    end

    error_group
    ingest_event do
      association :ingest_event,
                  project: error_group.project,
                  api_key: (api_key || association(:api_key, project: error_group.project, user: error_group.project.user)),
                  fingerprint: error_group.fingerprint,
                  message: error_group.title,
                  occurred_at: error_group.last_seen_at || Time.current
    end
    occurred_at { ingest_event.occurred_at }

    after(:create) do |occurrence|
      occurrence.ingest_event.update!(error_group: occurrence.error_group) if occurrence.ingest_event.error_group_id != occurrence.error_group_id

      group = occurrence.error_group
      group.update!(
        latest_event: group.latest_event || occurrence.ingest_event,
        first_seen_at: [ group.first_seen_at, occurrence.occurred_at ].compact.min,
        last_seen_at: [ group.last_seen_at, occurrence.occurred_at ].compact.max,
        occurrence_count: group.error_occurrences.count
      )
    end
  end
end

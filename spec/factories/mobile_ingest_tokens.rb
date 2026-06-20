# frozen_string_literal: true

FactoryBot.define do
  factory :mobile_ingest_token do
    association :project, :android
    api_key { create(:api_key, project: project, user: project.user) }
    platform { "android" }
    service { "com.example.app" }
    environment { "production" }
    release { "1.0.0+1" }
    session_id { "session-123" }
    allowed_event_types { MobileIngestToken::DEFAULT_ALLOWED_EVENT_TYPES }
    expires_at { 15.minutes.from_now }

    trait :ios do
      association :project, :ios
      platform { "ios" }
      service { "com.example.ios" }
    end

    trait :expired do
      after(:create) do |token|
        token.update_column(:expires_at, 1.minute.ago)
      end
    end

    trait :revoked do
      after(:create) do |token|
        token.update_column(:revoked_at, Time.current)
      end
    end
  end
end

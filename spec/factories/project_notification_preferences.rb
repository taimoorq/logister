# frozen_string_literal: true

FactoryBot.define do
  factory :project_notification_preference do
    association :project
    user { project.user }
    first_occurrence_enabled { true }
    digest_frequency { "none" }
    digest_send_hour { 9 }
    time_zone { "UTC" }
    send_empty_digest { false }

    trait :daily do
      digest_frequency { "daily" }
    end

    trait :weekly do
      digest_frequency { "weekly" }
    end
  end
end

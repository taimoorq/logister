# frozen_string_literal: true

FactoryBot.define do
  factory :email_notification_delivery do
    association :project
    user { project.user }
    notification_kind { "first_occurrence" }
    status { "pending" }
    sequence(:dedup_key) { |n| "delivery-#{n}" }

    transient do
      check_in_monitor { nil }
    end

    trait :first_occurrence do
      error_group { association(:error_group, :with_occurrence, project: project) }
      notification_kind { "first_occurrence" }
      dedup_key { EmailNotificationDelivery.first_occurrence_key(user: user, error_group: error_group) }
    end

    trait :daily_digest do
      notification_kind { "daily_digest" }
      period_start_at { 1.day.ago.beginning_of_day }
      period_end_at { Time.current.beginning_of_day }
      metadata do
        {
          "digest_frequency" => "daily",
          "period_start_at" => period_start_at.utc.iso8601,
          "period_end_at" => period_end_at.utc.iso8601
        }
      end
    end

    trait :regression do
      error_group { association(:error_group, :with_occurrence, project: project) }
      notification_kind { "regression" }
      dedup_key { EmailNotificationDelivery.notification_key(kind: notification_kind, user: user, project: project, subject: "#{error_group.id}:1") }
    end

    trait :monitor_missed do
      notification_kind { "monitor_missed" }
      metadata do
        monitor = check_in_monitor || create(:check_in_monitor, project: project)
        {
          "monitor_id" => monitor.id,
          "monitor_slug" => monitor.slug,
          "environment" => monitor.environment,
          "status" => monitor.status
        }
      end
    end

    trait :retention_failure do
      notification_kind { "retention_failure" }
      metadata do
        {
          "scope" => "hot_events",
          "record_type" => "ingest_events",
          "error_class" => "Logister::TelemetryArchiveExporter::Error",
          "error_message" => "storage unavailable"
        }
      end
    end
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :project_notification_preference do
    association :project
    user { project.user }
    first_occurrence_enabled { true }
    regression_enabled { true }
    frequent_error_enabled { false }
    frequent_error_threshold_count { 25 }
    frequent_error_window_minutes { 60 }
    milestone_alerts_enabled { false }
    workflow_mode { "assigned_to_me" }
    monitor_alerts_enabled { true }
    project_spike_enabled { false }
    project_spike_threshold_count { 100 }
    project_spike_window_minutes { 15 }
    performance_alerts_enabled { false }
    performance_p95_threshold_ms { 1_000 }
    release_notifications_enabled { false }
    usage_notifications_enabled { true }
    retention_notifications_enabled { true }
    environment_filter { "all" }
    severity_filter { "all" }
    status_filter { "unresolved" }
    immediate_email_limit_per_hour { 10 }
    quiet_hours_enabled { false }
    quiet_hours_start { 22 }
    quiet_hours_end { 7 }
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

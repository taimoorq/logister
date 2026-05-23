# frozen_string_literal: true

FactoryBot.define do
  factory :project_retention_policy do
    association :project
    hot_retention_days { 30 }
    trace_retention_days { 30 }
    error_retention_days { nil }
    archive_enabled { false }
    archive_before_delete { false }
  end
end

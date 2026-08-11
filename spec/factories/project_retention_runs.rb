# frozen_string_literal: true

FactoryBot.define do
  factory :project_retention_run do
    association :project
    scheduled_for { Time.current.change(usec: 0) }
    trigger_kind { "scheduled" }
    dry_run { false }
    status { "queued" }
    phase { "planning" }
    policy_snapshot { {} }
    cutoff_snapshot { {} }
    result { {} }
    metadata { {} }
  end
end

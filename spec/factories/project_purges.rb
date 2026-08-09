# frozen_string_literal: true

FactoryBot.define do
  factory :project_purge do
    association :project
    requested_by { project.user }
    source_project_id { project.id }
    project_uuid { project.uuid }
    project_name { project.name }
    idempotency_key { "project-purge/#{project.uuid}" }
    status { "tombstoned" }
    requested_at { Time.current }
    tombstoned_at { Time.current }
    configuration_snapshot { {} }
    audit_log { [] }

    after(:create) do |purge|
      ProjectPurge::STORE_ORDER.each_with_index do |store_name, position|
        purge.steps.find_or_create_by!(store_name: store_name) do |step|
          step.position = position
        end
      end
    end
  end
end

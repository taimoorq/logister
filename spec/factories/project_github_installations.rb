# frozen_string_literal: true

FactoryBot.define do
  factory :project_github_installation do
    association :project
    association :github_installation
    association :linked_by, factory: :user
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :project do
    association :user
    sequence(:name) { |n| "Project #{n}" }
    sequence(:slug) { |n| "project-#{n}" }
    description { nil }
  end
end

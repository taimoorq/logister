# frozen_string_literal: true

FactoryBot.define do
  factory :project_membership do
    association :project
    association :user
    role { :viewer }
  end
end

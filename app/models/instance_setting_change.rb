# frozen_string_literal: true

class InstanceSettingChange < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true

  validates :key, :action, :source, presence: true
end

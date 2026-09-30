# frozen_string_literal: true

# A project manager's decision that an optional setup step is not needed.
# Completion is never recorded here; it is derived from project evidence.
class ProjectSetupStep < ApplicationRecord
  STATUSES = %w[skipped].freeze

  belongs_to :project
  belongs_to :decided_by_user, class_name: "User", optional: true

  validates :key, presence: true, uniqueness: { scope: :project_id }
  validates :status, inclusion: { in: STATUSES }
  validate :key_is_skippable

  scope :skipped, -> { where(status: "skipped") }

  private

  def key_is_skippable
    return if key.blank?

    step = ProjectSetupCatalog.step(key)
    if step.nil?
      errors.add(:key, "is not a setup step")
    elsif step.personal
      errors.add(:key, "is personal to each person and cannot be skipped for the project")
    elsif step.group.required?
      errors.add(:key, "belongs to a required setup group and cannot be skipped")
    end
  end
end

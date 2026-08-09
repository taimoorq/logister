# frozen_string_literal: true

class EvidenceAccessAudit < ApplicationRecord
  ACTIONS = %w[download_unredacted_stored_evidence].freeze

  belongs_to :project
  belongs_to :user

  before_validation :ensure_uuid

  validates :uuid, :ingest_event_uuid, :ingest_event_occurred_at, :action, :reason, presence: true
  validates :uuid, uniqueness: true
  validates :action, inclusion: { in: ACTIONS }
  validates :reason, length: { minimum: 10, maximum: 500 }
  validate :user_can_manage_project

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def user_can_manage_project
    errors.add(:user, "must manage the project") unless project&.managed_by?(user)
  end
end

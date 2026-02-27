class ErrorOccurrence < ApplicationRecord
  belongs_to :error_group
  belongs_to :ingest_event

  before_validation :ensure_uuid
  before_validation :sync_occurred_at

  validates :uuid,           presence: true, uniqueness: true
  validates :ingest_event_id, uniqueness: { scope: :error_group_id }

  scope :recent_first, -> { order(occurred_at: :desc) }

  def to_param
    uuid
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def sync_occurred_at
    self.occurred_at ||= ingest_event&.occurred_at
  end
end

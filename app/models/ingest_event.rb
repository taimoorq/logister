class IngestEvent < ApplicationRecord
  belongs_to :project
  belongs_to :api_key

  before_validation :ensure_uuid

  enum :event_type, { error: 0, metric: 1 }, validate: true

  validates :uuid, presence: true, uniqueness: true
  validates :message, presence: true
  validates :occurred_at, presence: true

  def to_param
    uuid
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end

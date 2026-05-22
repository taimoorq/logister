class UserNotificationDismissal < ApplicationRecord
  belongs_to :user

  before_validation :ensure_uuid
  before_validation :ensure_dismissed_at

  validates :uuid, presence: true, uniqueness: true
  validates :notification_key, presence: true, length: { maximum: 200 }, uniqueness: { scope: :user_id }
  validates :dismissed_at, presence: true

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def ensure_dismissed_at
    self.dismissed_at ||= Time.current
  end
end

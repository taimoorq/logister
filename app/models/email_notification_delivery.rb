class EmailNotificationDelivery < ApplicationRecord
  KINDS = %w[first_occurrence daily_digest weekly_digest].freeze
  STATUSES = %w[pending sending sent skipped failed].freeze

  belongs_to :project
  belongs_to :user
  belongs_to :error_group, optional: true

  before_validation :ensure_uuid

  validates :uuid, presence: true, uniqueness: true
  validates :notification_kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :dedup_key, presence: true, uniqueness: true

  scope :sent, -> { where(status: "sent") }

  def self.first_occurrence_key(user:, error_group:)
    "first_occurrence:user:#{user.id}:error_group:#{error_group.id}"
  end

  def self.digest_key(preference:, period_start:, frequency:)
    start_key = period_start.in_time_zone("UTC").strftime("%Y%m%d%H%M%S")
    "digest:#{frequency}:user:#{preference.user_id}:project:#{preference.project_id}:#{start_key}"
  end

  def sent?
    status == "sent"
  end

  def sending_recent?
    status == "sending" && updated_at > 15.minutes.ago
  end

  def mark_sending!
    update!(status: "sending", last_error: nil)
  end

  def mark_sent!
    update!(status: "sent", sent_at: Time.current, last_error: nil)
  end

  def mark_skipped!(reason)
    update!(status: "skipped", last_error: reason)
  end

  def mark_failed!(error)
    update!(status: "failed", last_error: "#{error.class}: #{error.message}")
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end

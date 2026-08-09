class NotificationIntent < ApplicationRecord
  KINDS = %w[
    first_occurrence
    regression
    error_milestone
    monitor_missed
    monitor_recovered
  ].freeze
  ERROR_GROUP_KINDS = %w[first_occurrence regression error_milestone].freeze
  MONITOR_KINDS = %w[monitor_missed monitor_recovered].freeze
  STATUSES = %w[pending processing enqueued].freeze
  PROCESSING_LEASE = 10.minutes

  belongs_to :project
  belongs_to :error_group, optional: true
  belongs_to :check_in_monitor, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :dedup_key, presence: true, uniqueness: true
  validates :available_at, presence: true
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :subject_matches_kind
  validate :subject_belongs_to_project

  scope :ready, ->(now = Time.current) {
    pending = where(status: "pending").where("available_at <= ?", now)
    stale = where(status: "processing")
      .where("started_at IS NULL OR started_at <= ?", now - PROCESSING_LEASE)
    pending.or(stale)
  }

  def self.capture!(project:, kind:, dedup_key:, error_group: nil, check_in_monitor: nil, metadata: {}, available_at: Time.current)
    find_or_create_by!(dedup_key: dedup_key) do |intent|
      intent.project = project
      intent.kind = kind.to_s
      intent.error_group = error_group
      intent.check_in_monitor = check_in_monitor
      intent.metadata = metadata.stringify_keys
      intent.available_at = available_at
      intent.status = "pending"
    end
  end

  # Enqueue is only an accelerator. A failed Redis handoff leaves the committed
  # PostgreSQL intent pending for NotificationIntentSweepJob.
  def self.kick(intent)
    job = NotificationIntentDrainJob.perform_later(intent.id)
    return job if job && (!job.respond_to?(:successfully_enqueued?) || job.successfully_enqueued?)

    raise ActiveJob::EnqueueError, "notification intent #{intent.id} drainer was not enqueued"
  rescue StandardError => error
    Rails.logger.warn(
      "notification_intent.kick_failed intent_id=#{intent.id} " \
      "error=#{error.class}: #{error.message}"
    )
    nil
  end

  def claim!(now: Time.current)
    token = SecureRandom.uuid

    with_lock do
      return nil if status == "enqueued"
      return nil if status == "pending" && available_at > now
      if status == "processing" && started_at.present? && started_at > now - PROCESSING_LEASE
        return nil
      end

      update!(
        status: "processing",
        started_at: now,
        lease_token: token,
        attempts: attempts + 1,
        last_error: nil
      )
    end

    token
  end

  def mark_enqueued!(token, now: Time.current)
    with_lock do
      return false unless status == "processing" && lease_token.to_s == token.to_s

      update!(
        status: "enqueued",
        enqueued_at: now,
        started_at: nil,
        lease_token: nil,
        last_error: nil
      )
      true
    end
  end

  def release!(token, error, now: Time.current)
    with_lock do
      return false unless status == "processing" && lease_token.to_s == token.to_s

      delay = [ 2**[ attempts, 8 ].min, 300 ].min.seconds
      update!(
        status: "pending",
        available_at: now + delay,
        started_at: nil,
        lease_token: nil,
        last_error: "#{error.class}: #{error.message}".truncate(2_000)
      )
      true
    end
  end

  private

  def subject_matches_kind
    if ERROR_GROUP_KINDS.include?(kind)
      errors.add(:error_group, "must be present") if error_group.blank?
      errors.add(:check_in_monitor, "must be blank") if check_in_monitor.present?
    elsif MONITOR_KINDS.include?(kind)
      errors.add(:check_in_monitor, "must be present") if check_in_monitor.blank?
      errors.add(:error_group, "must be blank") if error_group.present?
    end
  end

  def subject_belongs_to_project
    if error_group.present? && error_group.project_id != project_id
      errors.add(:error_group, "must belong to the intent project")
    end
    if check_in_monitor.present? && check_in_monitor.project_id != project_id
      errors.add(:check_in_monitor, "must belong to the intent project")
    end
  end
end

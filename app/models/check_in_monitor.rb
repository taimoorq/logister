class CheckInMonitor < ApplicationRecord
  include CheckInMonitorRecording

  belongs_to :project
  belongs_to :last_event, class_name: "IngestEvent", optional: true
  has_many :notification_intents, dependent: :destroy

  before_validation :ensure_uuid
  validates :slug, presence: true
  validates :uuid, presence: true, uniqueness: true
  validates :environment, presence: true
  validates :expected_interval_seconds, numericality: { greater_than: 0 }
  validates :last_status, presence: true

  before_validation :sync_last_event_occurred_at

  scope :recent_first, -> { order(last_check_in_at: :desc) }
  scope :monitoring, -> { where(monitoring_paused_at: nil) }

  def missed?(at: Time.current)
    return false if monitoring_paused?
    return true if last_check_in_at.blank?
    return false if last_status == "error"

    deadline = last_check_in_at + expected_interval_seconds.seconds + grace_period
    at > deadline
  end

  def status(at: Time.current)
    return "paused" if monitoring_paused?
    return "error" if last_status == "error"
    return "missed" if missed?(at: at)

    "ok"
  end

  def monitoring_paused?
    monitoring_paused_at.present?
  end

  def pause_monitoring!
    with_lock do
      update!(
        monitoring_paused_at: Time.current,
        notification_state: "paused",
        notification_transition_id: SecureRandom.uuid
      )
    end
  end

  def resume_monitoring!
    with_lock do
      self.monitoring_paused_at = nil
      self.notification_state = status
      self.notification_transition_id = SecureRandom.uuid
      save!
    end
  end

  def last_event_record
    return if last_event_id.blank?
    if defined?(@last_event_record) &&
        @last_event_record&.id == last_event_id &&
        partition_timestamp_matches?(@last_event_record, last_event_occurred_at)
      return @last_event_record
    end

    loaded_event = association(:last_event).loaded? ? last_event : nil
    return loaded_event if loaded_event && partition_timestamp_matches?(loaded_event, last_event_occurred_at)

    @last_event_record = IngestEvent.for_partition_references(
      [ self ],
      id_key: :last_event_id,
      occurred_at_key: :last_event_occurred_at
    ).first
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def sync_last_event_occurred_at
    return if last_event_id.blank?
    return if last_event_occurred_at.present? && !will_save_change_to_last_event_id?

    event =
      if association(:last_event).loaded? && !will_save_change_to_last_event_id?
        last_event
      else
        IngestEvent.select(:id, :occurred_at).find_by(id: last_event_id)
      end
    self.last_event_occurred_at = event.occurred_at if event
  end

  def partition_timestamp_matches?(event, timestamp)
    timestamp.blank? || event.occurred_at.to_f == timestamp.to_f
  end

  def grace_period
    [ (expected_interval_seconds * 0.5).to_i.seconds, 30.seconds ].max
  end
end

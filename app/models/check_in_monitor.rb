class CheckInMonitor < ApplicationRecord
  belongs_to :project
  belongs_to :last_event, class_name: "IngestEvent", optional: true

  validates :slug, presence: true
  validates :environment, presence: true
  validates :expected_interval_seconds, numericality: { greater_than: 0 }
  validates :last_status, presence: true
  validates :slug, uniqueness: { scope: [ :project_id, :environment ] }

  before_validation :sync_last_event_occurred_at

  scope :recent_first, -> { order(last_check_in_at: :desc) }

  def missed?(at: Time.current)
    return true if last_check_in_at.blank?
    return false if last_status == "error"

    deadline = last_check_in_at + expected_interval_seconds.seconds + grace_period
    at > deadline
  end

  def status(at: Time.current)
    return "error" if last_status == "error"
    return "missed" if missed?(at: at)

    "ok"
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

  def self.record!(project:, event:)
    payload = extract_check_in_payload(event)
    return nil if payload[:slug].blank?

    monitor = project.check_in_monitors.find_or_initialize_by(
      slug: payload[:slug],
      environment: payload[:environment]
    )

    monitor.expected_interval_seconds = payload[:expected_interval_seconds]
    monitor.last_check_in_at = event.occurred_at
    monitor.last_status = payload[:status]
    monitor.last_error_at = payload[:status] == "error" ? event.occurred_at : monitor.last_error_at
    monitor.last_event = event
    monitor.last_event_occurred_at = event.occurred_at
    monitor.consecutive_missed_count = payload[:status] == "error" ? monitor.consecutive_missed_count : 0
    monitor.save!
    monitor
  end

  def self.extract_check_in_payload(event)
    ctx = event.context.is_a?(Hash) ? event.context : {}
    status = ctx["check_in_status"] || ctx[:check_in_status] || ctx["status"] || ctx[:status] || "ok"
    interval = ctx["expected_interval_seconds"] || ctx[:expected_interval_seconds] || 300
    slug = ctx["check_in_slug"] || ctx[:check_in_slug] || event.message
    environment = ctx["environment"] || ctx[:environment] || "production"

    {
      slug: slug.to_s.strip,
      status: status.to_s.strip.presence || "ok",
      expected_interval_seconds: interval.to_i.positive? ? interval.to_i : 300,
      environment: environment.to_s.strip.presence || "production"
    }
  end

  private

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

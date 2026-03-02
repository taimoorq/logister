class CheckInMonitor < ApplicationRecord
  belongs_to :project
  belongs_to :last_event, class_name: "IngestEvent", optional: true

  validates :slug, presence: true
  validates :environment, presence: true
  validates :expected_interval_seconds, numericality: { greater_than: 0 }
  validates :last_status, presence: true
  validates :slug, uniqueness: { scope: [ :project_id, :environment ] }

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

  def grace_period
    [ (expected_interval_seconds * 0.5).to_i.seconds, 30.seconds ].max
  end
end

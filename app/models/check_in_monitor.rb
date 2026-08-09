class CheckInMonitor < ApplicationRecord
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

  def self.record!(project:, event:)
    payload = extract_check_in_payload(event)
    return nil if payload[:slug].blank?

    monitor = nil
    intent = nil

    CheckInMonitor.transaction(requires_new: true) do
      monitor = project.check_in_monitors.create_or_find_by!(
        slug: payload[:slug],
        environment: payload[:environment]
      ) { |candidate| assign_event!(candidate, event, payload) }
      created = monitor.previously_new_record?

      monitor.with_lock do
        initial_event = created && same_event?(monitor, event)
        next unless initial_event || event_newer_than_monitor?(monitor, event)

        previous_status = initial_event ? nil : monitor.status(at: event.occurred_at)
        assign_event!(monitor, event, payload) unless initial_event
        current_status = monitor.status(at: event.occurred_at)

        if previous_status != current_status || monitor.notification_transition_id.blank?
          monitor.notification_state = current_status
          monitor.notification_transition_id = SecureRandom.uuid
        end
        monitor.save! if monitor.changed?

        intent = capture_status_transition_intent!(
          monitor,
          previous_status: previous_status,
          current_status: current_status,
          event: event
        )
      end
    end

    NotificationIntent.kick(intent) if intent
    monitor
  end

  def self.capture_missed_notification!(monitor:, detected_at: Time.current)
    bucket = detected_at.utc.strftime("%Y%m%d%H")
    intent = nil

    monitor.with_lock do
      project = monitor.project.reload
      next if project.notifications_disabled? || monitor.monitoring_paused?
      next unless monitor.status(at: detected_at) == "missed"

      if monitor.notification_state != "missed" || monitor.notification_transition_id.blank?
        monitor.update!(
          notification_state: "missed",
          notification_transition_id: SecureRandom.uuid
        )
      end

      transition_id = monitor.notification_transition_id
      intent = NotificationIntent.capture!(
        project: project,
        kind: "monitor_missed",
        check_in_monitor: monitor,
        dedup_key: "monitor:#{monitor.id}:transition:#{transition_id}:monitor_missed:bucket:#{bucket}",
        available_at: detected_at,
        metadata: {
          "transition_id" => transition_id,
          "expected_status" => "missed",
          "source_event_id" => monitor.last_event_id,
          "source_event_occurred_at" => monitor.last_event_occurred_at&.utc&.iso8601,
          "detected_at" => detected_at.utc.iso8601,
          "bucket" => bucket
        }.compact
      )
    end

    NotificationIntent.kick(intent) if intent && intent.status != "enqueued"
    intent
  end

  def self.assign_event!(monitor, event, payload)
    monitor.expected_interval_seconds = payload[:expected_interval_seconds]
    monitor.last_check_in_at = event.occurred_at
    monitor.last_status = payload[:status]
    monitor.last_error_at = event.occurred_at if payload[:status] == "error"
    monitor.last_event = event
    monitor.last_event_occurred_at = event.occurred_at
    monitor.consecutive_missed_count = 0 unless payload[:status] == "error"
  end
  private_class_method :assign_event!

  def self.same_event?(monitor, event)
    monitor.last_event_id == event.id && monitor.last_check_in_at == event.occurred_at
  end
  private_class_method :same_event?

  def self.event_newer_than_monitor?(monitor, event)
    return true if monitor.last_check_in_at.blank?
    return true if event.occurred_at > monitor.last_check_in_at
    return false if event.occurred_at < monitor.last_check_in_at

    event.id.to_i > monitor.last_event_id.to_i
  end
  private_class_method :event_newer_than_monitor?

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

  def self.capture_status_transition_intent!(monitor, previous_status:, current_status:, event:)
    transition_id = monitor.notification_transition_id

    if current_status == "error" && previous_status != "error"
      NotificationIntent.capture!(
        project: monitor.project,
        kind: "monitor_missed",
        check_in_monitor: monitor,
        dedup_key: "monitor:#{monitor.id}:transition:#{transition_id}:monitor_missed",
        metadata: {
          "transition_id" => transition_id,
          "expected_status" => "error",
          "event_id" => event.id,
          "event_uuid" => event.uuid,
          "event_occurred_at" => event.occurred_at.utc.iso8601,
          "detected_at" => event.occurred_at.utc.iso8601,
          "bucket" => event.occurred_at.utc.strftime("%Y%m%d%H")
        }
      )
    elsif current_status == "ok" && previous_status.in?(%w[error missed])
      NotificationIntent.capture!(
        project: monitor.project,
        kind: "monitor_recovered",
        check_in_monitor: monitor,
        dedup_key: "monitor:#{monitor.id}:transition:#{transition_id}:monitor_recovered",
        metadata: {
          "transition_id" => transition_id,
          "expected_status" => "ok",
          "event_id" => event.id,
          "event_uuid" => event.uuid,
          "event_occurred_at" => event.occurred_at.utc.iso8601,
          "recovered_at" => event.occurred_at.utc.iso8601
        }
      )
    end
  end
  private_class_method :capture_status_transition_intent!
end

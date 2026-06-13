class ErrorGroup < ApplicationRecord
  belongs_to :project
  belongs_to :latest_event, class_name: "IngestEvent", optional: true
  belongs_to :assignee, class_name: "User", foreign_key: :assigned_user_id, optional: true
  belongs_to :assigned_by, class_name: "User", foreign_key: :assigned_by_user_id, optional: true
  has_many   :error_occurrences, dependent: :destroy
  has_many   :ingest_events, through: :error_occurrences
  has_many   :email_notification_deliveries, dependent: :nullify

  before_validation :ensure_uuid
  before_validation :sync_latest_event_occurred_at

  # ── Status lifecycle ──────────────────────────────────────────────────────
  # unresolved → resolved  (mark_resolved!)
  # unresolved → ignored   (ignore!)
  # unresolved → archived  (archive!)
  # resolved   → unresolved (reopen!)  — also triggered automatically on new occurrence
  # ignored    → unresolved (reopen!)
  # archived   → unresolved (reopen!)
  enum :status, { unresolved: 0, resolved: 1, ignored: 2, archived: 3 }, validate: true

  # ── Validations ───────────────────────────────────────────────────────────
  validates :uuid,        presence: true, uniqueness: true
  validates :fingerprint, presence: true
  validates :title,       presence: true
  validates :status,      presence: true
  validates :fingerprint, uniqueness: { scope: :project_id }
  validate :assignee_has_project_access
  validate :assigner_has_project_access

  # ── Scopes ────────────────────────────────────────────────────────────────
  scope :open,              -> { where(status: [ :unresolved ]) }
  scope :for_inbox,         -> { open }
  scope :introduced_today,  -> { open.where("first_seen_at >= ?", Date.current.beginning_of_day) }
  scope :recent_first,      -> { order(last_seen_at: :desc, id: :desc) }
  scope :by_project,        ->(project) { where(project: project) }
  scope :assigned_to,       ->(user) { where(assigned_user_id: user&.id) }
  scope :unassigned,        -> { where(assigned_user_id: nil) }
  scope :with_occurrences,  -> { includes(:error_occurrences) }

  # 7-day trend — array of daily occurrence counts oldest→newest
  def trend(days: 7)
    start_date = days.days.ago.to_date
    counts_by_date = error_occurrences
      .where("occurred_at >= ?", start_date.beginning_of_day)
      .group("DATE(occurred_at)")
      .count

    (0...days).map do |offset|
      date = (start_date + offset).to_s
      counts_by_date[date] || 0
    end
  end

  # ── Lifecycle transitions ─────────────────────────────────────────────────
  def mark_resolved!
    update!(
      status: :resolved,
      resolved_at: Time.current,
      resolved_in_release: IngestEvent.release(latest_event_record)
    )
  end

  def ignore!
    update!(status: :ignored, ignored_at: Time.current)
  end

  def archive!
    update!(status: :archived, archived_at: Time.current)
  end

  def reopen!
    update!(
      status:           :unresolved,
      resolved_at:      nil,
      ignored_at:       nil,
      archived_at:      nil,
      last_reopened_at: Time.current,
      reopen_count:     reopen_count + 1
    )
  end

  def assign_to!(user, assigned_by:)
    update!(
      assignee: user,
      assigned_by: assigned_by,
      assigned_at: Time.current
    )
  end

  def clear_assignment!
    update!(
      assignee: nil,
      assigned_by: nil,
      assigned_at: nil
    )
  end

  # Called by the grouping service when a new occurrence arrives.
  # Reopens the group if it was previously resolved/ignored/archived.
  def record_occurrence!(event)
    was_closed = !unresolved?
    event_release = IngestEvent.release(event)

    with_lock do
      reopen! if was_closed
      update!(
        latest_event_id:  event.id,
        latest_event_occurred_at: event.occurred_at,
        last_seen_at:     event.occurred_at,
        first_seen_at:    [ first_seen_at, event.occurred_at ].compact.min,
        occurrence_count: occurrence_count + 1,
        title:            derive_title(event),
        subtitle:         derive_subtitle(event),
        stage:            derive_stage(event),
        severity:         event.level.presence || severity,
        last_seen_release: event_release.presence || last_seen_release,
        regressed_in_release: was_closed ? (event_release.presence || regressed_in_release) : regressed_in_release,
        regression_count: was_closed ? regression_count + 1 : regression_count
      )
    end
  end

  def to_param
    uuid
  end

  def latest_event_record
    return if latest_event_id.blank?
    if defined?(@latest_event_record) &&
        @latest_event_record&.id == latest_event_id &&
        partition_timestamp_matches?(@latest_event_record, latest_event_occurred_at)
      return @latest_event_record
    end

    loaded_event = association(:latest_event).loaded? ? latest_event : nil
    return loaded_event if loaded_event && partition_timestamp_matches?(loaded_event, latest_event_occurred_at)

    @latest_event_record = IngestEvent.for_partition_references(
      [ self ],
      id_key: :latest_event_id,
      occurred_at_key: :latest_event_occurred_at
    ).first
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def sync_latest_event_occurred_at
    return if latest_event_id.blank?
    return if latest_event_occurred_at.present? && !will_save_change_to_latest_event_id?

    event =
      if association(:latest_event).loaded? && !will_save_change_to_latest_event_id?
        latest_event
      else
        IngestEvent.select(:id, :occurred_at).find_by(id: latest_event_id)
      end
    self.latest_event_occurred_at = event.occurred_at if event
  end

  def partition_timestamp_matches?(event, timestamp)
    timestamp.blank? || event.occurred_at.to_f == timestamp.to_f
  end

  def assignee_has_project_access
    return if assignee.blank? || project&.assignable_user?(assignee)

    errors.add(:assignee, "must have access to this project")
  end

  def assigner_has_project_access
    return if assigned_by.blank? || project&.assignable_user?(assigned_by)

    errors.add(:assigned_by, "must have access to this project")
  end

  def derive_title(event)
    event.message.to_s.lines.first.to_s.strip.presence || title.presence || "Untitled error"
  end

  def derive_subtitle(event)
    ctx = event.context.is_a?(Hash) ? event.context : {}
    exc = ctx["exception"] || ctx[:exception]
    return nil unless exc.is_a?(Hash)

    exc["class"].presence || exc[:class].presence
  end

  def derive_stage(event)
    ctx = event.context.is_a?(Hash) ? event.context : {}
    ctx["environment"].presence || ctx[:environment].presence || "production"
  end
end

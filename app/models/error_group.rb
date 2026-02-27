class ErrorGroup < ApplicationRecord
  belongs_to :project
  belongs_to :latest_event, class_name: "IngestEvent", optional: true
  has_many   :error_occurrences, dependent: :destroy
  has_many   :ingest_events, through: :error_occurrences

  before_validation :ensure_uuid

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

  # ── Scopes ────────────────────────────────────────────────────────────────
  scope :open,              -> { where(status: [ :unresolved ]) }
  scope :for_inbox,         -> { open }
  scope :introduced_today,  -> { open.where("first_seen_at >= ?", Date.current.beginning_of_day) }
  scope :recent_first,      -> { order(last_seen_at: :desc) }
  scope :by_project,        ->(project) { where(project: project) }
  scope :with_occurrences,  -> { includes(:latest_event, :error_occurrences) }

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
    update!(status: :resolved, resolved_at: Time.current)
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

  # Called by the grouping service when a new occurrence arrives.
  # Reopens the group if it was previously resolved/ignored/archived.
  def record_occurrence!(event)
    was_closed = !unresolved?

    with_lock do
      reopen! if was_closed
      update!(
        latest_event_id:  event.id,
        last_seen_at:     event.occurred_at,
        first_seen_at:    [ first_seen_at, event.occurred_at ].compact.min,
        occurrence_count: occurrence_count + 1,
        title:            derive_title(event),
        subtitle:         derive_subtitle(event),
        stage:            derive_stage(event),
        severity:         event.level.presence || severity
      )
    end
  end

  def to_param
    uuid
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
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

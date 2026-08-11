# frozen_string_literal: true

require "digest"

class ProjectRetentionRun < ApplicationRecord
  STATUSES = %w[queued running waiting retrying completed failed cancelled superseded].freeze
  ACTIVE_STATUSES = %w[queued running waiting retrying].freeze
  TERMINAL_STATUSES = %w[completed failed cancelled superseded].freeze
  PHASES = %w[planning enumerating uploading verifying cleaning finalizing].freeze
  TRIGGER_KINDS = %w[scheduled manual recovery legacy].freeze
  SCOPES = %w[hot_events trace_spans error_events].freeze
  DEFAULT_STALE_SECONDS = 15.minutes.to_i

  belongs_to :project
  has_many :telemetry_archives, dependent: :nullify

  before_validation :set_run_key, on: :create

  validates :run_key, :scheduled_for, presence: true
  validates :run_key, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :phase, inclusion: { in: PHASES }
  validates :trigger_kind, inclusion: { in: TRIGGER_KINDS }
  validates :current_scope, inclusion: { in: SCOPES }, allow_nil: true
  validates :attempts, :fence_version, :objects_total, :objects_completed, :rows_total, :rows_completed,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :progress_does_not_exceed_totals

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :terminal, -> { where(status: TERMINAL_STATUSES) }
  scope :recoverable, -> { where(status: %w[queued running waiting retrying]) }
  scope :stale_before, lambda { |time|
    where("COALESCE(heartbeat_at, started_at, updated_at) < ?", time)
  }
  scope :recent_first, -> { order(scheduled_for: :desc, id: :desc) }

  def self.run_key_for(project_id:, scheduled_for:, dry_run:)
    scheduled_at = scheduled_for.in_time_zone("UTC").iso8601(6)
    Digest::SHA256.hexdigest("project-retention:v1:#{project_id}:#{scheduled_at}:#{dry_run ? 1 : 0}")
  end

  def self.stale_after
    seconds = Integer(ENV.fetch("LOGISTER_RETENTION_STALE_SECONDS", DEFAULT_STALE_SECONDS))
    (seconds.positive? ? seconds : DEFAULT_STALE_SECONDS).seconds
  rescue ArgumentError, TypeError
    DEFAULT_STALE_SECONDS.seconds
  end

  def terminal?
    status.in?(TERMINAL_STATUSES)
  end

  def active_run?
    status.in?(ACTIVE_STATUSES)
  end

  def stale?(before:)
    freshness = heartbeat_at || started_at || updated_at
    freshness.present? && freshness < before
  end

  private

  def set_run_key
    return if run_key.present? || project_id.blank? || scheduled_for.blank?

    self.run_key = self.class.run_key_for(
      project_id: project_id,
      scheduled_for: scheduled_for,
      dry_run: dry_run?
    )
  end

  def progress_does_not_exceed_totals
    errors.add(:objects_completed, "cannot exceed total objects") if objects_completed.to_i > objects_total.to_i
    errors.add(:rows_completed, "cannot exceed total rows") if rows_completed.to_i > rows_total.to_i
  end
end

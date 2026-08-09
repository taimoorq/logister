# frozen_string_literal: true

class ProjectPurge < ApplicationRecord
  STATUSES = %w[requested tombstoned running awaiting_external verifying completed failed].freeze
  TERMINAL_STATUSES = %w[completed failed].freeze
  # Keep the PostgreSQL control plane (including ownership and the durable
  # recovery handle) until external ClickHouse cleanup has been verified.
  # Redis-derived state remains last so no earlier cleanup can recreate it.
  STORE_ORDER = %w[archives clickhouse postgresql redis].freeze

  belongs_to :project, optional: true
  belongs_to :requested_by, class_name: "User", optional: true
  has_many :steps,
           -> { order(:position) },
           class_name: "ProjectPurgeStep",
           dependent: :destroy,
           inverse_of: :project_purge

  validates :project_uuid, :source_project_id, :project_name, :idempotency_key, :requested_at, presence: true
  validates :idempotency_key, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :source_project_id, numericality: { only_integer: true, greater_than: 0 }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where.not(status: TERMINAL_STATUSES) }
  scope :recent_first, -> { order(created_at: :desc) }

  def terminal?
    status.in?(TERMINAL_STATUSES)
  end

  def completed?
    status == "completed"
  end

  def awaiting_external?
    status == "awaiting_external"
  end

  def append_audit!(event, details = {}, at: Time.current)
    with_lock do
      entries = Array(audit_log).dup
      entries << {
        "event" => event.to_s,
        "at" => at.utc.iso8601(6),
        "details" => details.as_json
      }
      update!(audit_log: entries)
    end
  end
end

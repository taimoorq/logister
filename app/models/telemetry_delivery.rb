# frozen_string_literal: true

class TelemetryDelivery < ApplicationRecord
  include TelemetryDeliveryBatches

  class LeaseExpired < StandardError; end
  class BatchOwnershipLost < StandardError; end

  DESTINATIONS = %w[
    clickhouse_event
    clickhouse_span
    deployment_index
    error_grouping
    check_in_monitor
  ].freeze
  CLICKHOUSE_DESTINATIONS = %w[clickhouse_event clickhouse_span].freeze
  SYNCHRONOUS_DESTINATIONS = %w[deployment_index error_grouping check_in_monitor].freeze
  MAX_ATTEMPTS = 8
  MAX_RETRY_DELAY = 15.minutes
  DEFAULT_LEASE = 2.minutes

  before_validation :ensure_uuid

  belongs_to :project
  belongs_to :telemetry_outbox_event

  enum :status, {
    pending: "pending",
    processing: "processing",
    retrying: "retrying",
    completed: "completed",
    terminal_failed: "terminal_failed"
  }, validate: true

  validates :uuid, :destination, :status, :available_at, presence: true
  validates :uuid, uniqueness: true
  validates :destination, inclusion: { in: DESTINATIONS }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :incomplete, -> { where.not(status: :completed) }
  scope :terminal_failures, -> { where(status: :terminal_failed) }
  scope :required_for_replay, -> { where(replay_required_predicate) }

  def claim!(now: Time.current, lease_for: DEFAULT_LEASE)
    with_lock do
      return false unless claimable?(now)

      update!(
        status: :processing,
        attempts: attempts + 1,
        leased_at: now,
        lease_expires_at: now + lease_for,
        lease_token: SecureRandom.uuid
      )
    end
    true
  end

  def assign_batch_key!(value)
    with_lock do
      self.batch_key ||= value
      save! if changed?
    end
    batch_key
  end

  def mark_completed!(lease_token: self.lease_token, at: Time.current)
    transaction do
      lock!
      return true if completed?
      return false unless owned_processing_lease?(lease_token)

      update!(
        status: :completed,
        completed_at: at,
        leased_at: nil,
        lease_expires_at: nil,
        lease_token: nil,
        available_at: at
      )
      TelemetryProjectionWatermark.record_delivered!(self, at: at)
    end
    true
  end

  def mark_failed!(error, lease_token: self.lease_token, terminal: nil, at: Time.current)
    transaction do
      lock!
      return false unless owned_processing_lease?(lease_token)

      terminal = attempts >= MAX_ATTEMPTS unless terminal.in?([ true, false ])
      terminal ||= attempts >= MAX_ATTEMPTS
      attributes = {
        status: terminal ? :terminal_failed : :retrying,
        available_at: terminal ? at : at + retry_delay,
        terminal_failed_at: terminal ? at : nil,
        last_error_at: at,
        last_error_class: error.class.name,
        last_error_message: error.message.to_s.first(4_000),
        leased_at: nil,
        lease_expires_at: nil,
        lease_token: nil
      }
      update!(attributes)
      TelemetryProjectionWatermark.record_terminal_failure!(self, at: at) if terminal
    end
    true
  end

  def replay!(at: Time.current, metadata: {})
    transaction do
      lock!
      was_terminal = terminal_failed?
      update!(
        status: :pending,
        attempts: 0,
        available_at: at,
        leased_at: nil,
        lease_expires_at: nil,
        lease_token: nil,
        terminal_failed_at: nil,
        metadata: self.metadata.to_h.merge(metadata.to_h.stringify_keys)
      )
      TelemetryProjectionWatermark.clear_terminal_failure!(self, at: at) if was_terminal
    end
    self
  end

  def retry_delay
    [ 2**[ attempts, 10 ].min, MAX_RETRY_DELAY.to_i ].min.seconds
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def claimable?(now)
    return attempts < MAX_ATTEMPTS && available_at <= now if pending? || retrying?

    processing? && attempts < MAX_ATTEMPTS && lease_expires_at.present? && lease_expires_at <= now
  end

  def owned_processing_lease?(token)
    processing? && lease_token.present? && ActiveSupport::SecurityUtils.secure_compare(lease_token, token.to_s)
  end
end

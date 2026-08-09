# frozen_string_literal: true

class TelemetryProjectionWatermark < ApplicationRecord
  RETENTION = 90.days
  ACCEPTED_INCREMENT_SQL = <<~SQL.squish.freeze
    accepted_count = accepted_count + 1,
    accepted_checksum = accepted_checksum + CAST(? AS numeric),
    last_accepted_at = ?,
    updated_at = ?
  SQL
  DELIVERED_INCREMENT_SQL = <<~SQL.squish.freeze
    delivered_count = delivered_count + 1,
    delivered_checksum = delivered_checksum + CAST(? AS numeric),
    last_delivered_at = ?,
    updated_at = ?
  SQL

  belongs_to :project

  validates :signal, :destination, :bucket_start_at, presence: true
  validates :accepted_count, :delivered_count, :terminal_failure_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_clickhouse, -> { where(destination: TelemetryDelivery::CLICKHOUSE_DESTINATIONS) }

  class << self
    def record_accepted!(delivery, at: Time.current)
      checksum = identity_checksum_for(delivery)
      mutate_for_delivery!(delivery) do |watermark|
        where(id: watermark.id).update_all([ ACCEPTED_INCREMENT_SQL, checksum.to_s, at, at ])
        watermark.refresh_completion!
      end
    end

    def record_delivered!(delivery, at: Time.current)
      checksum = identity_checksum_for(delivery)
      mutate_for_delivery!(delivery) do |watermark|
        where(id: watermark.id).update_all([ DELIVERED_INCREMENT_SQL, checksum.to_s, at, at ])
        watermark.refresh_completion!
      end
    end

    def record_terminal_failure!(delivery, at: Time.current)
      mutate_for_delivery!(delivery) do |watermark|
        where(id: watermark.id).update_all(
          [ "terminal_failure_count = terminal_failure_count + 1, updated_at = ?", at ]
        )
        watermark.refresh_completion!
      end
    end

    def clear_terminal_failure!(delivery, at: Time.current)
      mutate_for_delivery!(delivery) do |watermark|
        where(id: watermark.id).update_all(
          [ "terminal_failure_count = GREATEST(terminal_failure_count - 1, 0), updated_at = ?", at ]
        )
        watermark.refresh_completion!
      end
    end

    def identity_checksum(client_identifier)
      client_identifier.to_s.delete("-").to_i(16)
    end

    def seal_empty!(project_id:, signal:, destination:, bucket_start_at:, at: Time.current)
      watermark = create_or_find_by!(
        project_id: project_id,
        signal: signal,
        destination: destination,
        bucket_start_at: bucket_start_at.utc.beginning_of_hour
      )
      watermark.with_lock do
        next :non_empty unless watermark.accepted_count.zero? &&
          watermark.delivered_count.zero? &&
          watermark.terminal_failure_count.zero?

        watermark.update!(complete_at: watermark.complete_at || at)
        :sealed
      end
    end

    private

    def identity_checksum_for(delivery)
      outbox_event = delivery.telemetry_outbox_event
      record_identifier = outbox_event.metadata.to_h["record_identifier"].presence || outbox_event.client_identifier
      identity_checksum(record_identifier)
    end

    def mutate_for_delivery!(delivery)
      attempts = 0
      begin
        watermark = find_for_delivery!(delivery)
        watermark.with_lock { yield watermark }
      rescue ActiveRecord::RecordNotFound
        attempts += 1
        retry if attempts < 3

        raise
      end
    end

    def find_for_delivery!(delivery)
      outbox_event = delivery.telemetry_outbox_event
      create_or_find_by!(
        project_id: delivery.project_id,
        signal: outbox_event.signal,
        destination: delivery.destination,
        bucket_start_at: outbox_event.recorded_at.utc.beginning_of_hour
      )
    end
  end

  def complete?
    complete_at.present? && completion_candidate?
  end

  def refresh_completion!
    reload
    desired = completion_candidate? ? (complete_at || Time.current) : nil
    update_column(:complete_at, desired) if complete_at != desired
    self
  end

  def lag_count
    [ accepted_count - delivered_count, 0 ].max
  end

  private

  def completion_candidate?
    (accepted_count.positive? || complete_at.present?) &&
      delivered_count == accepted_count &&
      delivered_checksum == accepted_checksum &&
      terminal_failure_count.zero?
  end
end

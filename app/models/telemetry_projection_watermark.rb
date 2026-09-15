# frozen_string_literal: true

class TelemetryProjectionWatermark < ApplicationRecord
  include TelemetryProjectionRecording

  RETENTION = 90.days
  # Owned by one acceptance transaction. Flush only after every source and intent
  # has been persisted, so hot bucket locks are held only at the commit boundary.
  class AcceptanceBatch
    def initialize
      @acceptances = []
    end

    def record_accepted!(delivery, at: Time.current)
      @acceptances << [ delivery, at ]
    end

    def flush!
      TelemetryProjectionWatermark.record_accepted_batch!(@acceptances)
      @acceptances.clear
    end
  end

  belongs_to :project

  validates :signal, :destination, :bucket_start_at, presence: true
  validates :accepted_count, :delivered_count, :terminal_failure_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_clickhouse, -> { where(destination: TelemetryDelivery::CLICKHOUSE_DESTINATIONS) }

  class << self
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

    def seal_empty!(project_id:, signal:, destination:, bucket_start_at:, at: Time.current)
      identity = {
        project_id: project_id,
        signal: signal,
        destination: destination,
        bucket_start_at: bucket_start_at.utc.beginning_of_hour
      }
      watermark = find_by(identity) || create_or_find_by!(identity)
      watermark.with_lock do
        next :non_empty unless watermark.accepted_count.zero? &&
          watermark.delivered_count.zero? &&
          watermark.terminal_failure_count.zero?

        watermark.update!(complete_at: watermark.complete_at || at)
        :sealed
      end
    end

    private

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
      identity = identity_for_delivery(delivery)
      find_by(identity) || create_or_find_by!(identity)
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

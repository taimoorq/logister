class ErrorOccurrence < ApplicationRecord
  belongs_to :error_group
  belongs_to :ingest_event

  before_validation :ensure_uuid
  before_validation :sync_ingest_event_timestamps

  validates :uuid,           presence: true, uniqueness: true
  validates :ingest_event_id, uniqueness: { scope: :error_group_id }

  scope :recent_first, -> { order(occurred_at: :desc) }

  def to_param
    uuid
  end

  def ingest_event_record
    if defined?(@ingest_event_record) &&
        @ingest_event_record&.id == ingest_event_id &&
        partition_timestamp_matches?(@ingest_event_record, ingest_event_occurred_at)
      return @ingest_event_record
    end

    loaded_event = association(:ingest_event).loaded? ? ingest_event : nil
    return loaded_event if loaded_event && partition_timestamp_matches?(loaded_event, ingest_event_occurred_at)

    @ingest_event_record = IngestEvent.for_partition_references(
      [ self ],
      id_key: :ingest_event_id,
      occurred_at_key: :ingest_event_occurred_at
    ).first
  end

  def ingest_event_record=(event)
    @ingest_event_record = event
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def sync_ingest_event_timestamps
    return if ingest_event_id.blank?
    return if occurred_at.present? && ingest_event_occurred_at.present? && !will_save_change_to_ingest_event_id?

    event =
      if association(:ingest_event).loaded?
        ingest_event
      else
        IngestEvent.for_partition_references(
          [ self ],
          id_key: :ingest_event_id,
          occurred_at_key: :ingest_event_occurred_at
        ).first || ingest_event
      end
    return unless event

    self.occurred_at ||= event.occurred_at
    self.ingest_event_occurred_at = event.occurred_at
  end

  def partition_timestamp_matches?(event, timestamp)
    timestamp.blank? || event.occurred_at.to_f == timestamp.to_f
  end
end

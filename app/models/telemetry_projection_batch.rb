# frozen_string_literal: true

require "digest"
require "stringio"
require "zlib"

# A short-lived copy of the exact HTTP body, committed before external delivery.
# Retain it through ambiguous outcomes, partial legacy ACKs and source changes;
# remove it with the final ACK, or during periodic cleanup after an old worker.
class TelemetryProjectionBatch < ApplicationRecord
  class InvalidPayload < StandardError; end

  MAX_ROWS = 200
  # Legacy one-row batches allowed a 1 MiB JSON row plus its trailing newline.
  MAX_BYTES = 1.megabyte + 1

  belongs_to :project

  def self.prepare!(deliveries:, members: deliveries, batch_key:, payload:)
    ids = members.map(&:id)
    unless ids.uniq.length == ids.length && ids.length.between?(1, MAX_ROWS) &&
      payload.bytesize.between?(1, MAX_BYTES) && (deliveries.map(&:id) - ids).empty? &&
      members.map { |delivery| [ delivery.project_id, delivery.destination ] }.uniq.one? &&
      members.first.destination.in?(TelemetryDelivery::CLICKHOUSE_DESTINATIONS)
      raise InvalidPayload, "Invalid projection batch membership or size"
    end

    identity = members.first.attributes.symbolize_keys.slice(:project_id, :destination).merge(batch_key: batch_key)
    digest = Digest::SHA256.hexdigest(payload)
    transaction do
      batch = create_or_find_by!(identity) do |candidate|
        candidate.delivery_ids = ids
        candidate.compressed_payload = Zlib.gzip(payload)
        candidate.payload_sha256 = digest
        candidate.payload_bytes = payload.bytesize
      end
      batch.with_lock do
        unless batch.delivery_ids == ids && batch.payload_sha256 == digest
          raise InvalidPayload, "Persisted projection batch is immutable"
        end

        TelemetryDelivery.assign_batch_key_batch!(deliveries, batch_key: batch_key)
      end
      batch
    end
  end

  def self.cleanup_completed!
    where(<<~SQL.squish).delete_all
      NOT EXISTS (
        SELECT 1 FROM telemetry_deliveries d
        WHERE d.project_id = telemetry_projection_batches.project_id
          AND d.destination = telemetry_projection_batches.destination
          AND d.batch_key = telemetry_projection_batches.batch_key
          AND d.status <> 'completed'
      )
    SQL
  end

  def payload
    body = Zlib::GzipReader.wrap(StringIO.new(compressed_payload)) { |gzip| gzip.read(MAX_BYTES + 1) }
    unless body.bytesize == payload_bytes && body.bytesize <= MAX_BYTES && Digest::SHA256.hexdigest(body) == payload_sha256
      raise InvalidPayload, "Persisted projection payload failed verification"
    end

    body.force_encoding(Encoding::UTF_8)
    raise InvalidPayload, "Persisted projection payload is not UTF-8" unless body.valid_encoding?

    body
  rescue Zlib::Error, Zlib::GzipFile::Error => error
    raise InvalidPayload, "Persisted projection payload cannot be decoded: #{error.class}"
  end

  def acknowledge!(deliveries, at: Time.current)
    unless deliveries.all? { |delivery| delivery.project_id == project_id && delivery.destination == destination && delivery_ids.include?(delivery.id) }
      raise InvalidPayload, "Acknowledgement does not belong to this projection batch"
    end

    with_lock do
      ids = TelemetryDelivery.mark_completed_batch!(deliveries, at: at)
      destroy! unless TelemetryDelivery.where(id: delivery_ids).where.not(status: :completed).exists?
      ids
    end
  end
end

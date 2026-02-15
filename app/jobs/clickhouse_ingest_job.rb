class ClickhouseIngestJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(ingest_event_id, request_context = {})
    event = IngestEvent.find(ingest_event_id)
    Logister::EventIngestor.new(event: event, request_context: request_context.symbolize_keys).call
  rescue Logister::ClickhouseClient::Error => e
    Rails.logger.error("clickhouse_ingest_error event_id=#{ingest_event_id} error=#{e.message}")
  end
end

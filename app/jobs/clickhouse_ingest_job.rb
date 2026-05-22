class ClickhouseIngestJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(ingest_event_id, request_context = {})
    event = IngestEvent.find(ingest_event_id)
    Logister::EventIngestor.new(event: event, request_context: request_context.symbolize_keys).call
  rescue Logister::ClickhouseClient::Error => e
    Rails.logger.error("clickhouse_ingest_error event_id=#{ingest_event_id} error=#{e.message}")
    report_clickhouse_ingest_failure(ingest_event_id, e)
  end

  private

  def report_clickhouse_ingest_failure(ingest_event_id, error)
    Logister::ClickhouseFailureReporter.new(
      kind: "event",
      subject_key: :ingest_event_id,
      subject_id: ingest_event_id,
      error: error,
      log_message: "ClickHouse ingest failed",
      log_fingerprint: "logister:clickhouse_ingest:failure",
      metric_name: "logister.clickhouse.ingest_failure",
      metric_fingerprint: "logister:metric:clickhouse_ingest_failure"
    ).call
  end
end

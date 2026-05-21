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
    context = {
      clickhouse_ingest: {
        ingest_event_id: ingest_event_id,
        error: {
          class: error.class.name,
          message: error.message
        }
      }
    }

    Logister.report_log(
      message: "ClickHouse ingest failed",
      level: "error",
      fingerprint: "logister:clickhouse_ingest:failure",
      context: context
    )
    Logister.report_metric(
      message: "logister.clickhouse.ingest_failure",
      level: "error",
      fingerprint: "logister:metric:clickhouse_ingest_failure",
      context: context.merge(
        metric: {
          name: "logister.clickhouse.ingest_failure",
          value: 1,
          unit: "count"
        },
        value: 1,
        unit: "count"
      )
    )
  rescue StandardError => report_error
    Rails.logger.warn("clickhouse ingest monitoring failed: #{report_error.class} #{report_error.message}")
  end
end

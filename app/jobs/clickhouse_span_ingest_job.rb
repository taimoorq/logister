class ClickhouseSpanIngestJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(trace_span_id, request_context = {})
    span = TraceSpan.find(trace_span_id)
    Logister::SpanIngestor.new(span: span, request_context: request_context.symbolize_keys).call
  rescue Logister::ClickhouseClient::Error => e
    Rails.logger.error("clickhouse_span_ingest_error trace_span_id=#{trace_span_id} error=#{e.message}")
    report_clickhouse_span_ingest_failure(trace_span_id, e)
  end

  private

  def report_clickhouse_span_ingest_failure(trace_span_id, error)
    context = {
      clickhouse_ingest: {
        trace_span_id: trace_span_id,
        error: {
          class: error.class.name,
          message: error.message
        }
      }
    }

    Logister.report_log(
      message: "ClickHouse span ingest failed",
      level: "error",
      fingerprint: "logister:clickhouse_span_ingest:failure",
      context: context
    )
    Logister.report_metric(
      message: "logister.clickhouse.span_ingest_failure",
      level: "error",
      fingerprint: "logister:metric:clickhouse_span_ingest_failure",
      context: context.merge(
        metric: {
          name: "logister.clickhouse.span_ingest_failure",
          value: 1,
          unit: "count"
        },
        value: 1,
        unit: "count"
      )
    )
  rescue StandardError => report_error
    Rails.logger.warn("clickhouse span ingest monitoring failed: #{report_error.class} #{report_error.message}")
  end
end

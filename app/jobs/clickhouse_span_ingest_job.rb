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
    Logister::ClickhouseFailureReporter.new(
      kind: "span",
      subject_key: :trace_span_id,
      subject_id: trace_span_id,
      error: error,
      log_message: "ClickHouse span ingest failed",
      log_fingerprint: "logister:clickhouse_span_ingest:failure",
      metric_name: "logister.clickhouse.span_ingest_failure",
      metric_fingerprint: "logister:metric:clickhouse_span_ingest_failure"
    ).call
  end
end

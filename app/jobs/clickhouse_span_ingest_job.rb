class ClickhouseSpanIngestJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(trace_span_id, request_context = {})
    span = TraceSpan.find(trace_span_id)
    Logister::SpanIngestor.new(span: span, request_context: request_context.symbolize_keys).call
  rescue Logister::ClickhouseClient::Error => e
    Rails.logger.error("clickhouse_span_ingest_error trace_span_id=#{trace_span_id} error=#{e.message}")
    Logister::ClickhouseFailureReporter.report_span_failure(trace_span_id, e)
  end
end

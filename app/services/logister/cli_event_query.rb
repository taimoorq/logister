# frozen_string_literal: true

module Logister
  class CliEventQuery
    CONTEXT_BYTES_LIMIT = 64.kilobytes
    MESSAGE_LENGTH_LIMIT = 4_096
    FINGERPRINT_LENGTH_LIMIT = 512

    BASE_PROJECTION_SQL = <<~SQL.squish.freeze
      ingest_events.id,
      ingest_events.project_id,
      ingest_events.uuid,
      ingest_events.event_type,
      LEFT(ingest_events.level, 32) AS level,
      LEFT(ingest_events.message, #{MESSAGE_LENGTH_LIMIT}) AS message,
      LEFT(ingest_events.fingerprint, #{FINGERPRINT_LENGTH_LIMIT}) AS fingerprint,
      ingest_events.occurred_at,
      ingest_events.created_at,
      ingest_events.error_group_id
    SQL

    SUMMARY_CONTEXT_SQL = <<~SQL.squish.freeze
      jsonb_strip_nulls(jsonb_build_object(
        'environment', LEFT(ingest_events.context->>'environment', 100),
        'release', LEFT(ingest_events.context->>'release', 200),
        'transaction_name', LEFT(COALESCE(
          ingest_events.context->>'transaction_name',
          ingest_events.context->>'transactionName'
        ), 512),
        'trace_id', LEFT(COALESCE(
          ingest_events.context->>'trace_id',
          ingest_events.context->>'traceId',
          ingest_events.context->'trace'->>'traceId'
        ), 128),
        'request_id', LEFT(COALESCE(
          ingest_events.context->>'request_id',
          ingest_events.context->>'requestId',
          ingest_events.context->'trace'->>'requestId'
        ), 200),
        'session_id', LEFT(COALESCE(
          ingest_events.context->>'session_id',
          ingest_events.context->>'sessionId'
        ), 200),
        'user_id', LEFT(COALESCE(
          ingest_events.context->>'user_id',
          ingest_events.context->>'userId',
          ingest_events.context->'user'->>'id'
        ), 200),
        'duration_ms', CASE
          WHEN octet_length(COALESCE(
            ingest_events.context->>'duration_ms',
            ingest_events.context->>'durationMs',
            ''
          )) <= 64
          THEN COALESCE(ingest_events.context->'duration_ms', ingest_events.context->'durationMs')
        END,
        'status', CASE
          WHEN octet_length(COALESCE(ingest_events.context->>'status', '')) <= 64
          THEN ingest_events.context->'status'
        END,
        'check_in_status', CASE
          WHEN octet_length(COALESCE(ingest_events.context->>'check_in_status', '')) <= 64
          THEN ingest_events.context->'check_in_status'
        END
      ))
    SQL

    SUMMARY_CONTEXT_PROJECTION_SQL = "#{SUMMARY_CONTEXT_SQL} AS context".freeze
    SUMMARY_TRUNCATION_PROJECTION_SQL = "FALSE AS cli_context_truncated"
    BOUNDED_CONTEXT_PROJECTION_SQL = <<~SQL.squish.freeze
      CASE
        WHEN octet_length(ingest_events.context::text) <= #{CONTEXT_BYTES_LIMIT}
        THEN ingest_events.context
        ELSE #{SUMMARY_CONTEXT_SQL}
      END AS context
    SQL
    BOUNDED_TRUNCATION_PROJECTION_SQL = <<~SQL.squish.freeze
      octet_length(ingest_events.context::text) > #{CONTEXT_BYTES_LIMIT} AS cli_context_truncated
    SQL

    class << self
      def summary(scope)
        scope.reselect(
          Arel.sql(BASE_PROJECTION_SQL),
          Arel.sql(SUMMARY_CONTEXT_PROJECTION_SQL),
          Arel.sql(SUMMARY_TRUNCATION_PROJECTION_SQL)
        )
      end

      def bounded_context(scope)
        scope.reselect(
          Arel.sql(BASE_PROJECTION_SQL),
          Arel.sql(BOUNDED_CONTEXT_PROJECTION_SQL),
          Arel.sql(BOUNDED_TRUNCATION_PROJECTION_SQL)
        )
      end
    end
  end
end

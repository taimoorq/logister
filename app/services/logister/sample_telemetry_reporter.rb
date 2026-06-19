# frozen_string_literal: true

require "securerandom"
require "pathname"

module Logister
  class SampleTelemetryReporter
    SAMPLE_TAGS = { category: "self_test", source: "rails" }.freeze
    SAMPLE_CHECK_IN = "logister.self_test"

    class SampleError < StandardError; end

    class << self
      def call(source_context: SourceContext.current)
        new(source_context: source_context).call
      end
    end

    def initialize(source_context:)
      @source_context = source_context
    end

    def call
      trace_id = SecureRandom.hex(16)
      request_id = "sample-#{SecureRandom.hex(8)}"
      started_at = Time.now.utc

      Logister.add_breadcrumb(
        category: "self_test",
        message: "Starting Logister sample telemetry burst",
        data: base_context
      )
      Logister.add_dependency(
        name: "github.contents",
        host: "api.github.com",
        method: "GET",
        status: 200,
        duration_ms: 42.7,
        kind: "http",
        data: { repository: source_context.repository }
      )

      results = {}
      results[:deployment] = DeploymentRecorder.call(source_context.deployment_payload)
      results[:log] = report_log(trace_id: trace_id, request_id: request_id)
      results[:metric] = report_metric(trace_id: trace_id, request_id: request_id)
      results[:transaction] = report_transaction(trace_id: trace_id, request_id: request_id)
      results[:spans] = report_spans(trace_id: trace_id, request_id: request_id, started_at: started_at)
      results[:check_in] = report_check_in(trace_id: trace_id, request_id: request_id)
      results[:error] = report_error(trace_id: trace_id, request_id: request_id)
      results[:flushed] = Logister.flush(timeout: 2)
      results
    end

    private

    attr_reader :source_context

    def report_log(trace_id:, request_id:)
      Logister.report_log(
        message: "Logister sample telemetry log",
        level: "info",
        fingerprint: "logister:self_test:log",
        context: base_context.merge(trace_id: trace_id, request_id: request_id),
        tags: SAMPLE_TAGS
      )
    end

    def report_metric(trace_id:, request_id:)
      Logister.report_metric(
        message: "logister.self_test.sample_value",
        value: 1,
        unit: "count",
        level: "info",
        fingerprint: "logister:self_test:metric",
        context: base_context.merge(trace_id: trace_id, request_id: request_id),
        tags: SAMPLE_TAGS
      )
    end

    def report_transaction(trace_id:, request_id:)
      Logister.report_transaction(
        name: "logister.self_test.transaction",
        duration_ms: 128.4,
        status: 200,
        level: "info",
        fingerprint: "logister:self_test:transaction",
        context: base_context.merge(
          trace_id: trace_id,
          request_id: request_id,
          route: "logister:self_test",
          method: "RAKE"
        ),
        tags: SAMPLE_TAGS
      )
    end

    def report_spans(trace_id:, request_id:, started_at:)
      root_span_id = SecureRandom.hex(8)
      root_started_at = started_at - 0.2

      [
        Logister.report_span(
          name: "logister.self_test.root",
          kind: "server",
          status: "ok",
          trace_id: trace_id,
          request_id: request_id,
          span_id: root_span_id,
          duration_ms: 128.4,
          started_at: root_started_at,
          ended_at: root_started_at + 0.1284,
          context: base_context.merge(route: "logister:self_test"),
          tags: SAMPLE_TAGS
        ),
        child_span(
          name: "logister.self_test.db",
          kind: "db",
          duration_ms: 18.2,
          trace_id: trace_id,
          request_id: request_id,
          parent_span_id: root_span_id,
          context: { table: "project_source_repositories" }
        ),
        child_span(
          name: "logister.self_test.github",
          kind: "http",
          duration_ms: 42.7,
          trace_id: trace_id,
          request_id: request_id,
          parent_span_id: root_span_id,
          context: { host: "api.github.com", method: "GET" }
        ),
        child_span(
          name: "logister.self_test.queue",
          kind: "queue",
          duration_ms: 9.3,
          trace_id: trace_id,
          request_id: request_id,
          parent_span_id: root_span_id,
          context: { queue: "default" }
        )
      ]
    end

    def child_span(name:, kind:, duration_ms:, trace_id:, request_id:, parent_span_id:, context:)
      Logister.report_span(
        name: name,
        kind: kind,
        status: "ok",
        trace_id: trace_id,
        request_id: request_id,
        parent_span_id: parent_span_id,
        duration_ms: duration_ms,
        context: base_context.merge(context),
        tags: SAMPLE_TAGS
      )
    end

    def report_check_in(trace_id:, request_id:)
      Logister.report_check_in(
        slug: SAMPLE_CHECK_IN,
        status: "ok",
        expected_interval_seconds: 3600,
        duration_ms: 128.4,
        trace_id: trace_id,
        request_id: request_id,
        context: base_context.merge(scheduler: { name: SAMPLE_CHECK_IN, sample: true })
      )
    end

    def report_error(trace_id:, request_id:)
      Logister.report_error(
        sample_error,
        level: "error",
        fingerprint: "logister:self_test:error",
        context: base_context.merge(
          trace_id: trace_id,
          request_id: request_id,
          sample_error: true
        ),
        tags: SAMPLE_TAGS
      )
    end

    def sample_error
      error = SampleError.new("Synthetic Logister sample telemetry error")
      relative_file = Pathname.new(__FILE__).relative_path_from(Rails.root).to_s
      error.set_backtrace([
        "#{relative_file}:#{__LINE__}:in `sample_error'",
        "app/services/logister/sample_telemetry_reporter.rb:1:in `call'"
      ])
      error
    end

    def base_context
      {
        sample_telemetry: {
          name: "logister.self_test",
          repository: source_context.repository,
          commit_sha: source_context.commit_sha,
          branch: source_context.branch,
          release: source_context.release,
          environment: source_context.environment
        }.compact,
        service: source_context.service,
        repository: source_context.repository,
        commit_sha: source_context.commit_sha,
        branch: source_context.branch,
        release: source_context.release,
        environment: source_context.environment
      }.compact
    end
  end
end

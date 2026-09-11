# frozen_string_literal: true

require "securerandom"
require "pathname"

module Logister
  class SampleTelemetryReporter
    SAMPLE_TAGS = { category: "self_test", source: "rails" }.freeze

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
      results = {}
      results[:error] = report_error(trace_id: trace_id, request_id: request_id)
      results[:flushed] = Logister.flush(timeout: 2)
      results
    end

    private

    attr_reader :source_context

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

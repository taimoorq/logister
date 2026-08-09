# frozen_string_literal: true

module Logister
  class ErrorGroupAiContext
    RELATED_LOG_LIMIT = 20
    FRAME_LIMIT = 20
    DEFAULT_TOKEN_BUDGET = 4_000
    MIN_TOKEN_BUDGET = 256
    MAX_TOKEN_BUDGET = 32_000
    BYTES_PER_TOKEN = 4
    MAX_RESPONSE_BYTES = 256.kilobytes

    def self.call(project:, group:, logister_url: nil, token_budget: nil)
      new(project: project, group: group, logister_url: logister_url, token_budget: token_budget).call
    end

    def initialize(project:, group:, logister_url:, token_budget:)
      @project = project
      @group = group
      @logister_url = logister_url
      parsed_budget = token_budget.to_i
      @token_budget = parsed_budget.between?(MIN_TOKEN_BUDGET, MAX_TOKEN_BUDGET) ? parsed_budget : DEFAULT_TOKEN_BUDGET
    end

    def call
      export = Logister::TelemetryRedactor.call(
        ErrorGroupJsonExporter.call(
          project: project,
          group: group,
          include_occurrences: false,
          logister_url: logister_url
        )
      )

      payload = {
        format: "logister_ai_context",
        version: 1,
        generated_at: Time.current.utc.iso8601(6),
        token_budget: token_budget,
        response_byte_limit: response_byte_limit,
        truncated: false,
        project: export["project"],
        issue: export["error_group"],
        assignment: export["assignment"],
        latest_event: minimized_event(export["latest_event"]),
        exception: minimized_exception(export["exception"]),
        request: export["request"],
        occurrences: export["occurrences"],
        related_logs: minimized_related_logs(export["related_logs"]),
        deployment_context: export["deployment_context"],
        external_links: export["external_links"],
        notes: [
          "Payload is server-redacted. Sensitive-looking keys are replaced with [REDACTED].",
          "Use timestamps, release, trace_id, request_id, and related logs as investigation anchors."
        ]
      }.compact
      bounded = Logister::BoundedJsonPayload.call(
        payload,
        max_bytes: response_byte_limit,
        max_string_bytes: 8.kilobytes,
        max_array_items: RELATED_LOG_LIMIT
      )
      bounded.value["truncated"] = bounded.truncated
      bounded.value
    end

    private

    attr_reader :project, :group, :logister_url, :token_budget

    def response_byte_limit
      [ token_budget * BYTES_PER_TOKEN, MAX_RESPONSE_BYTES ].min
    end

    def minimized_event(event)
      return nil unless event

      event.slice(
        "uuid",
        "event_type",
        "level",
        "message",
        "fingerprint",
        "occurred_at",
        "environment",
        "release",
        "transaction_name",
        "trace_id",
        "request_id",
        "context"
      )
    end

    def minimized_exception(exception)
      return nil unless exception

      {
        "data" => exception["data"],
        "application_frames" => Array(exception["application_frames"]).first(FRAME_LIMIT)
      }
    end

    def minimized_related_logs(related_logs)
      records = Array(related_logs&.fetch("records", []))

      {
        "window_seconds" => related_logs&.fetch("window_seconds", nil),
        "count" => related_logs&.fetch("count", records.size),
        "record_limit" => RELATED_LOG_LIMIT,
        "records" => records.first(RELATED_LOG_LIMIT).map { |event| minimized_event(event) }
      }.compact
    end
  end
end

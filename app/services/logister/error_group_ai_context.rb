# frozen_string_literal: true

module Logister
  class ErrorGroupAiContext
    RELATED_LOG_LIMIT = 20
    FRAME_LIMIT = 20

    def self.call(project:, group:, logister_url: nil, token_budget: nil)
      new(project: project, group: group, logister_url: logister_url, token_budget: token_budget).call
    end

    def initialize(project:, group:, logister_url:, token_budget:)
      @project = project
      @group = group
      @logister_url = logister_url
      @token_budget = token_budget.to_i.positive? ? token_budget.to_i : nil
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

      {
        format: "logister_ai_context",
        version: 1,
        generated_at: Time.current.utc.iso8601(6),
        token_budget: token_budget,
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
    end

    private

    attr_reader :project, :group, :logister_url, :token_budget

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

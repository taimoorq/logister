# frozen_string_literal: true

module Logister
  class CliSerializer
    class << self
      def project(project)
        {
          uuid: project.uuid,
          name: project.name,
          slug: project.slug,
          description: project.description,
          integration_kind: project.integration_kind,
          integration_label: project.integration_label,
          archived: project.archived?,
          archived_at: timestamp(project.archived_at),
          created_at: timestamp(project.created_at),
          updated_at: timestamp(project.updated_at)
        }.compact
      end

      def event(event, include_context: true)
        payload = {
          uuid: event.uuid,
          event_type: event.event_type,
          level: event.level,
          message: event.message,
          fingerprint: event.fingerprint,
          occurred_at: timestamp(event.occurred_at),
          created_at: timestamp(event.created_at),
          environment: IngestEvent.environment(event, nil),
          release: IngestEvent.release(event),
          transaction_name: IngestEvent.transaction_name(event),
          trace_id: IngestEvent.trace_id(event),
          request_id: IngestEvent.request_id(event),
          session_id: IngestEvent.session_id(event),
          user_identifier: IngestEvent.user_identifier(event),
          duration_ms: duration_ms(event),
          status: event_status(event),
          error_group_uuid: event.error_group&.uuid
        }.compact

        payload[:context] = redacted(event.context) if include_context
        if event.has_attribute?(:cli_context_truncated) && ActiveModel::Type::Boolean.new.cast(event[:cli_context_truncated])
          payload[:context_truncated] = true
        end
        payload
      end

      def error_group(group, latest_event: nil)
        {
          uuid: group.uuid,
          fingerprint: group.fingerprint,
          title: group.title,
          subtitle: group.subtitle,
          stage: group.stage,
          severity: group.severity,
          status: group.status,
          occurrence_count: group.occurrence_count,
          first_seen_at: timestamp(group.first_seen_at),
          last_seen_at: timestamp(group.last_seen_at),
          resolved_at: timestamp(group.resolved_at),
          ignored_at: timestamp(group.ignored_at),
          archived_at: timestamp(group.archived_at),
          reopen_count: group.reopen_count,
          last_reopened_at: timestamp(group.last_reopened_at),
          regression_count: group.regression_count,
          introduced_in_release: group.introduced_in_release,
          last_seen_release: group.last_seen_release,
          regressed_in_release: group.regressed_in_release,
          assigned_to: user(group.assignee),
          latest_event: latest_event && event(latest_event, include_context: false)
        }.compact
      end

      def occurrence_summary(group)
        occurrence_scope = group.error_occurrences

        {
          total_count: group.occurrence_count,
          stored_count: occurrence_scope.count,
          first_occurrence_at: timestamp(occurrence_scope.minimum(:occurred_at) || group.first_seen_at),
          last_occurrence_at: timestamp(occurrence_scope.maximum(:occurred_at) || group.last_seen_at)
        }
      end

      def trace_span(span, include_context: false)
        context = span.context.is_a?(Hash) ? span.context : {}
        payload = {
          uuid: span.uuid,
          trace_id: span.trace_id,
          span_id: span.span_id,
          parent_span_id: span.parent_span_id,
          name: span.name,
          operation: span.route_name,
          kind: span.kind,
          status: normalized_trace_status(span.status),
          duration_ms: span.duration_ms.to_f.round(3),
          started_at: timestamp(span.started_at),
          ended_at: timestamp(span.ended_at),
          environment: context["environment"].presence || context[:environment].presence || "production",
          release: context["release"].presence || context[:release].presence,
          service: context["service"].presence || context[:service].presence || span.project.slug,
          request_id: span.request_id
        }.compact
        payload[:context] = redacted(context) if include_context
        payload
      end

      def monitor(monitor, at:, last_event: nil)
        {
          uuid: monitor.uuid,
          slug: monitor.slug,
          environment: monitor.environment,
          status: monitor.status(at:),
          expected_interval_seconds: monitor.expected_interval_seconds,
          last_check_in_at: timestamp(monitor.last_check_in_at),
          last_error_at: timestamp(monitor.last_error_at),
          last_event: last_event && event(last_event, include_context: false),
          created_at: timestamp(monitor.created_at),
          updated_at: timestamp(monitor.updated_at)
        }.compact
      end

      def deployment(deployment, previous_deployment: nil)
        {
          uuid: deployment.uuid,
          provider: deployment.provider,
          repository_full_name: deployment.repository_full_name,
          environment: deployment.environment,
          release: deployment.release,
          commit_sha: deployment.commit_sha,
          short_commit_sha: deployment.short_commit_sha,
          branch: deployment.branch,
          deployed_at: timestamp(deployment.deployed_at || deployment.created_at),
          source: deployment.source,
          metadata: redacted(deployment.metadata),
          links: {
            commit: deployment.github_commit_url,
            pull_request: deployment.pull_request_url,
            release: deployment.release_url,
            compare: deployment.compare_url(previous_deployment)
          }.compact,
          previous_deployment: previous_deployment && {
            uuid: previous_deployment.uuid,
            release: previous_deployment.release,
            commit_sha: previous_deployment.commit_sha,
            deployed_at: timestamp(previous_deployment.deployed_at || previous_deployment.created_at)
          }
        }.compact
      end

      def analytics(read)
        coverage = read.respond_to?(:coverage) ? read.coverage : nil
        {
          source: read.respond_to?(:source) ? read.source : nil,
          coverage: coverage && {
            complete: coverage.complete?,
            ratio: coverage.coverage_ratio,
            fresh_through: timestamp(coverage.fresh_through)
          },
          partial: false
        }.compact
      end

      def user(user)
        return nil unless user

        {
          uuid: user.uuid,
          name: user.name
        }.compact
      end

      def redacted(value)
        Logister::TelemetryRedactor.call(value.as_json)
      end

      def timestamp(value)
        value&.to_time&.utc&.iso8601(6)
      end

      def duration_ms(event)
        raw = context_value(event, "duration_ms").presence || context_value(event, "durationMs").presence
        return if raw.blank?

        Float(raw)
      rescue ArgumentError, TypeError
        nil
      end

      def event_status(event)
        context_value(event, "status").presence || context_value(event, "check_in_status").presence
      end

      def normalized_trace_status(value)
        value.to_s.presence_in(%w[ok error]) || "unset"
      end

      def context_value(event, key)
        context = event.context.is_a?(Hash) ? event.context : {}
        context[key] || context[key.to_sym]
      end
    end
  end
end

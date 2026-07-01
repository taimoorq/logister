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
        value&.utc&.iso8601(6)
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

      def context_value(event, key)
        context = event.context.is_a?(Hash) ? event.context : {}
        context[key] || context[key.to_sym]
      end
    end
  end
end

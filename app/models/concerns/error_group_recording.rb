# frozen_string_literal: true

module ErrorGroupRecording
  # Compatibility wrapper for callers that only need the regression result.
  def record_occurrence!(event)
    record_occurrence_with_policy!(event).reopen_group?
  end

  def record_occurrence_with_policy!(event)
    event_release = IngestEvent.release(event)
    evidence = TelemetryEvidence.for(event)
    decision = nil

    with_lock do
      decision = ErrorGroupOccurrencePolicy.new(group: self, event: event).call
      previous_status = status
      closure_at = [ resolved_at, ignored_at, archived_at ].compact.max
      reopen! if decision.reopen_group?

      changes = { occurrence_count: occurrence_count + 1 }
      if decision.update_source_bounds?
        source_start = evidence.reporting_start || event.occurred_at
        source_end = evidence.reporting_end || event.occurred_at
        changes[:first_seen_at] = [ first_seen_at, source_start ].compact.min
        changes[:last_seen_at] = [ last_seen_at, source_end ].compact.max
      end
      if decision.update_latest?
        changes.merge!(
          latest_event_id: event.id,
          latest_event_occurred_at: event.occurred_at,
          title: ErrorGroupEventDetails.title(event, fallback: title),
          subtitle: ErrorGroupEventDetails.subtitle(event),
          stage: ErrorGroupEventDetails.stage(event),
          severity: event.level.presence || severity,
          last_seen_release: event_release.presence || last_seen_release
        )
      end
      if decision.reopen_group?
        changes[:regressed_in_release] = event_release.presence || regressed_in_release
        changes[:regression_count] = regression_count + 1
        changes[:current_regression] = regression_evidence(
          event: event,
          evidence: evidence,
          decision: decision,
          previous_status: previous_status,
          closure_at: closure_at,
          release: event_release
        )
      end
      update!(changes)
    end

    decision
  end

  private

  def regression_evidence(event:, evidence:, decision:, previous_status:, closure_at:, release:)
    proof_at = if evidence.reporting_interval?
      evidence.reporting_start
    elsif evidence.exact_time? || decision.reason == :source_evidence_after_closure
      evidence.occurred_at || event.occurred_at
    end

    {
      "schema_version" => 1,
      "reason" => "after_#{previous_status}",
      "policy_reason" => decision.reason.to_s,
      "time_precision" => evidence.time_precision,
      "proof_at" => proof_at&.utc&.iso8601(6),
      "closure_at" => closure_at&.utc&.iso8601(6),
      "received_at" => (evidence.received_at || event.created_at)&.utc&.iso8601(6),
      "detected_at" => Time.current.utc.iso8601(6),
      "event_uuid" => event.uuid,
      "source" => evidence.source,
      "kind" => evidence.kind,
      "release" => release
    }.compact
  end
end

# frozen_string_literal: true

class ErrorGroupOccurrencePolicy
  LEGACY_NEAR_REALTIME_TOLERANCE = 15.minutes

  class Decision < Data.define(
    :reopen_group,
    :update_latest,
    :update_source_bounds,
    :workflow_alerts,
    :reason
  )
    def reopen_group? = reopen_group
    def update_latest? = update_latest
    def update_source_bounds? = update_source_bounds
    def workflow_alerts? = workflow_alerts
  end

  attr_reader :group, :event, :evidence

  def initialize(group:, event:)
    @group = group
    @event = event
    @evidence = TelemetryEvidence.for(event)
  end

  def call
    source_bounds = exact_source_time? || evidence.reporting_interval?
    update_latest = source_bounds && latest_source_evidence?
    reopen_group = group_closed? && provably_after_closure?

    Decision.new(
      reopen_group: reopen_group,
      update_latest: update_latest,
      update_source_bounds: source_bounds,
      workflow_alerts: group_closed? ? reopen_group : update_latest,
      reason: reason(reopen_group: reopen_group, update_latest: update_latest)
    ).freeze
  end

  private

  def exact_source_time?
    evidence.exact_time? || legacy_near_realtime?
  end

  def legacy_near_realtime?
    return false unless evidence.time_precision == "unknown"
    return false unless event.occurred_at && event.created_at

    (event.created_at - event.occurred_at).abs <= LEGACY_NEAR_REALTIME_TOLERANCE
  end

  def latest_source_evidence?
    current = group.latest_event_occurred_at || group.last_seen_at
    current.nil? || event.occurred_at >= current
  end

  def group_closed?
    !group.unresolved?
  end

  def provably_after_closure?
    closed_at = closure_time
    return false unless closed_at

    if exact_source_time?
      event.occurred_at > closed_at
    elsif evidence.reporting_interval?
      evidence.reporting_start.present? && evidence.reporting_start > closed_at
    else
      false
    end
  end

  def closure_time
    [ group.resolved_at, group.ignored_at, group.archived_at ].compact.max
  end

  def reason(reopen_group:, update_latest:)
    return :source_evidence_after_closure if reopen_group
    return :received_only if evidence.received_only?
    return :legacy_time_unknown if evidence.time_precision == "unknown"
    return :reporting_interval_overlaps_closure if evidence.reporting_interval? && group_closed?
    return :source_evidence_before_closure if group_closed?
    return :latest_source_evidence if update_latest

    :historical_source_evidence
  end
end

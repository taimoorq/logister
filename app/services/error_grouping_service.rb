# Upserts an ErrorGroup for an ingest event and creates an ErrorOccurrence link.
#
# Grouping key priority:
#   1. event.fingerprint  (explicitly set by the SDK)
#   2. first line of event.message  (best-effort for unfingerprinted errors)
#
# Call ErrorGroupingService.call(event) immediately after the event is saved.
#
class ErrorGroupingService
  RECORD_NOT_UNIQUE_RETRIES = 2

  # Returns the ErrorGroup that was created or updated.
  def self.call(event, notifications: true)
    new(event, notifications: notifications).call
  end

  def initialize(event, notifications: true)
    @event   = event
    @project = event.project
    @notifications = notifications
  end

  def call
    return nil unless @event.error?

    attempts = 0
    group = created = occurrence_created = regressed = nil
    occurrence_decision = nil
    notification_intents = []
    evaluation_to_schedule = nil

    begin
      notification_intents = []
      evaluation_to_schedule = nil
      occurrence_decision = nil
      regressed = nil
      fingerprint = derive_fingerprint
      ErrorGroup.transaction(requires_new: true) do
        group, created = upsert_group(fingerprint)
        occurrence, occurrence_created = link_occurrence(group)

        if !created && occurrence_created
          occurrence_decision = group.record_occurrence_with_policy!(@event)
          regressed = occurrence_decision.reopen_group?
        end

        # Back-link on the ingest_event row so we can JOIN cheaply
        @event.update_column(:error_group_id, group.id)

        workflow_alerts = created || occurrence_decision&.workflow_alerts?
        if @notifications && occurrence_created && workflow_alerts
          notification_intents = capture_notification_intents(
            group,
            occurrence: occurrence,
            created: created,
            regressed: regressed,
            workflow_alerts: workflow_alerts
          )
          unless created
            evaluation, schedule = NotificationEvaluation.observe_frequent_error!(
              error_group: group,
              occurred_at: @event.occurred_at
            )
            evaluation_to_schedule = evaluation if schedule
          end
        end
      end
    rescue ActiveRecord::RecordNotUnique
      raise if attempts >= RECORD_NOT_UNIQUE_RETRIES

      attempts += 1
      @event.reload
      retry
    end

    notification_intents.each { |intent| NotificationIntent.kick(intent) }
    schedule_frequent_error_evaluation(evaluation_to_schedule) if evaluation_to_schedule
    if occurrence_created && (@project.integration_android? || @project.integration_ios?)
      schedule_mobile_event_enrichment
    end
    group
  end

  private

  def derive_fingerprint
    @grouping_evidence = grouping_evidence

    @event.fingerprint.presence ||
      @grouping_evidence&.fingerprint.presence ||
      @event.message.to_s.lines.first.to_s.strip.presence ||
      @event.uuid
  end

  # find-or-create the ErrorGroup. Existing groups are counted only after a new
  # occurrence link is created, which keeps retries and duplicate workers idempotent.
  def upsert_group(fingerprint)
    aliases = @grouping_evidence&.respond_to?(:fingerprint_aliases) ? @grouping_evidence.fingerprint_aliases : []
    group = @project.error_groups.where(fingerprint: [ fingerprint, *aliases ]).first
    group ||= @project.error_groups.new(fingerprint: fingerprint)

    created = group.new_record?

    if created
      # Build initial state from the event
      ctx = @event.context.is_a?(Hash) ? @event.context : {}
      exc = ctx["exception"] || ctx[:exception]
      evidence = TelemetryEvidence.for(@event)
      source_start = evidence.reporting_start || @event.occurred_at
      source_end = evidence.reporting_end || @event.occurred_at

      group.assign_attributes(
        title:           @event.message.to_s.lines.first.to_s.strip.presence || "Untitled error",
        subtitle:        exc.is_a?(Hash) ? (exc["class"].presence || exc[:class].presence || exc["type"].presence || exc[:type].presence) : nil,
        stage:           ctx["environment"].presence || ctx[:environment].presence || "production",
        severity:        @event.level.presence || "error",
        introduced_in_release: IngestEvent.release(@event),
        last_seen_release: IngestEvent.release(@event),
        status:          :unresolved,
        first_seen_at:   source_start,
        last_seen_at:    source_end,
        latest_event_id: @event.id,
        latest_event_occurred_at: @event.occurred_at,
        occurrence_count: 1
      )
      if @grouping_evidence&.usable?
        group.grouping_algorithm_version = @grouping_evidence.class::VERSION
        group.grouping_evidence = @grouping_evidence.evidence
      end
      group.save!
    end

    [ group, created ]
  end

  def link_occurrence(group)
    occurrence = ErrorOccurrence.find_by(
      error_group:  group,
      ingest_event: @event
    )
    return [ occurrence, false ] if occurrence

    occurrence = ErrorOccurrence.create!(
      error_group: group,
      ingest_event: @event,
      occurred_at: @event.occurred_at,
      ingest_event_occurred_at: @event.occurred_at,
      **occurrence_dimensions
    )
    [ occurrence, true ]
  end

  def android_grouping_evidence
    AndroidErrorGroupingEvidence.new(@event)
  end

  def grouping_evidence
    return android_grouping_evidence if @project.integration_android?
    return IosErrorGroupingEvidence.new(@event) if @project.integration_ios?

    nil
  end

  def occurrence_dimensions
    return {} unless ErrorOccurrence.column_names.include?("dimensions")

    ErrorOccurrenceDimensions.new(@event).attributes
  end

  def milestone_reached?(count)
    count == 10 || count == 100 || count == 1_000 || (count > 1_000 && (count % 1_000).zero?)
  end

  def capture_notification_intents(group, occurrence:, created:, regressed:, workflow_alerts:)
    intents = []
    if created
      intents << NotificationIntent.capture!(
        project: @project,
        kind: "first_occurrence",
        error_group: group,
        dedup_key: "error_group:#{group.id}:first_occurrence",
        metadata: occurrence_identity_metadata(occurrence)
      )
    end
    if regressed
      intents << NotificationIntent.capture!(
        project: @project,
        kind: "regression",
        error_group: group,
        dedup_key: "error_group:#{group.id}:regression:event:#{@event.uuid}",
        metadata: regression_metadata(group, occurrence)
      )
    end
    if workflow_alerts && milestone_reached?(group.occurrence_count)
      intents << NotificationIntent.capture!(
        project: @project,
        kind: "error_milestone",
        error_group: group,
        dedup_key: "error_group:#{group.id}:milestone:#{group.occurrence_count}",
        metadata: milestone_metadata(group, occurrence)
      )
    end
    intents
  end

  def occurrence_identity_metadata(occurrence)
    evidence = TelemetryEvidence.for(@event)
    dimensions = occurrence&.dimensions.to_h
    {
      "event_id" => @event.id,
      "event_uuid" => @event.uuid,
      "occurred_at" => @event.occurred_at.utc.iso8601,
      "received_at" => evidence.received_at&.utc&.iso8601,
      "time_precision" => evidence.time_precision,
      "reporting_start" => evidence.reporting_start&.utc&.iso8601,
      "reporting_end" => evidence.reporting_end&.utc&.iso8601,
      "evidence_source" => evidence.source,
      "diagnostic_kind" => dimensions["diagnostic_kind"],
      "build_number" => dimensions["build_number"],
      "distribution_channel" => dimensions["distribution_channel"],
      "artifact_state" => dimensions["mapping_status"].presence || dimensions["symbolication_status"].presence
    }.compact
  end

  def schedule_frequent_error_evaluation(evaluation)
    NotificationEvaluation.schedule_frequent_error!(evaluation)
  rescue StandardError => error
    Rails.logger.warn(
      "notification_evaluation.schedule_failed evaluation_id=#{evaluation.id} " \
      "error=#{error.class}: #{error.message}"
    )
    nil
  end

  def schedule_mobile_event_enrichment
    MobileEventEnrichmentJob.perform_later(@project.id, @event.uuid, @event.occurred_at.utc.iso8601(6))
  rescue StandardError => error
    Rails.logger.warn(
      "mobile_event_enrichment.schedule_failed project_id=#{@project.id} event_uuid=#{@event.uuid} " \
      "error=#{error.class}: #{error.message}"
    )
    nil
  end

  def regression_metadata(group, occurrence)
    occurrence_identity_metadata(occurrence).merge(
      "event_id" => @event.id,
      "event_uuid" => @event.uuid,
      "occurred_at" => @event.occurred_at.utc.iso8601,
      "reopen_count" => group.reopen_count,
      "release" => IngestEvent.release(@event)
    ).compact
  end

  def milestone_metadata(group, occurrence)
    occurrence_identity_metadata(occurrence).merge(
      "event_id" => @event.id,
      "event_uuid" => @event.uuid,
      "occurred_at" => @event.occurred_at.utc.iso8601,
      "milestone" => group.occurrence_count
    )
  end
end

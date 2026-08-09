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
    notification_intents = []
    evaluation_to_schedule = nil

    begin
      notification_intents = []
      evaluation_to_schedule = nil
      fingerprint = derive_fingerprint
      ErrorGroup.transaction(requires_new: true) do
        group, created = upsert_group(fingerprint)
        _occurrence, occurrence_created = link_occurrence(group)

        if !created && occurrence_created
          regressed = group.record_occurrence!(@event)
        end

        # Back-link on the ingest_event row so we can JOIN cheaply
        @event.update_column(:error_group_id, group.id)

        if @notifications && occurrence_created
          notification_intents = capture_notification_intents(
            group,
            created: created,
            regressed: regressed
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
    group = @project.error_groups.find_or_initialize_by(fingerprint: fingerprint)

    created = group.new_record?

    if created
      # Build initial state from the event
      ctx = @event.context.is_a?(Hash) ? @event.context : {}
      exc = ctx["exception"] || ctx[:exception]

      group.assign_attributes(
        title:           @event.message.to_s.lines.first.to_s.strip.presence || "Untitled error",
        subtitle:        exc.is_a?(Hash) ? (exc["class"].presence || exc[:class].presence || exc["type"].presence || exc[:type].presence) : nil,
        stage:           ctx["environment"].presence || ctx[:environment].presence || "production",
        severity:        @event.level.presence || "error",
        introduced_in_release: IngestEvent.release(@event),
        last_seen_release: IngestEvent.release(@event),
        status:          :unresolved,
        first_seen_at:   @event.occurred_at,
        last_seen_at:    @event.occurred_at,
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

  def capture_notification_intents(group, created:, regressed:)
    intents = []
    if created
      intents << NotificationIntent.capture!(
        project: @project,
        kind: "first_occurrence",
        error_group: group,
        dedup_key: "error_group:#{group.id}:first_occurrence",
        metadata: occurrence_identity_metadata
      )
    end
    if regressed
      intents << NotificationIntent.capture!(
        project: @project,
        kind: "regression",
        error_group: group,
        dedup_key: "error_group:#{group.id}:regression:event:#{@event.uuid}",
        metadata: regression_metadata(group)
      )
    end
    if milestone_reached?(group.occurrence_count)
      intents << NotificationIntent.capture!(
        project: @project,
        kind: "error_milestone",
        error_group: group,
        dedup_key: "error_group:#{group.id}:milestone:#{group.occurrence_count}",
        metadata: milestone_metadata(group)
      )
    end
    intents
  end

  def occurrence_identity_metadata
    {
      "event_id" => @event.id,
      "event_uuid" => @event.uuid,
      "occurred_at" => @event.occurred_at.utc.iso8601
    }
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

  def regression_metadata(group)
    {
      "event_id" => @event.id,
      "event_uuid" => @event.uuid,
      "occurred_at" => @event.occurred_at.utc.iso8601,
      "reopen_count" => group.reopen_count,
      "release" => IngestEvent.release(@event)
    }.compact
  end

  def milestone_metadata(group)
    {
      "event_id" => @event.id,
      "event_uuid" => @event.uuid,
      "occurred_at" => @event.occurred_at.utc.iso8601,
      "milestone" => group.occurrence_count
    }
  end
end

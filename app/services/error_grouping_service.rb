# Upserts an ErrorGroup for an ingest event and creates an ErrorOccurrence link.
#
# Grouping key priority:
#   1. event.fingerprint  (explicitly set by the SDK)
#   2. first line of event.message  (best-effort for unfingerprinted errors)
#
# Call ErrorGroupingService.call(event) immediately after the event is saved.
#
class ErrorGroupingService
  # Returns the ErrorGroup that was created or updated.
  def self.call(event)
    new(event).call
  end

  def initialize(event)
    @event   = event
    @project = event.project
  end

  def call
    return nil unless @event.error?

    fingerprint = derive_fingerprint
    group, created, regressed = upsert_group(fingerprint)
    link_occurrence(group)
    ProjectErrorFirstOccurrenceAlertJob.perform_later(group.id) if created
    ProjectErrorGroupNotificationJob.perform_later(group.id, "regression", regression_metadata(group)) if regressed
    ProjectErrorGroupNotificationJob.perform_later(group.id, "error_milestone", milestone_metadata(group)) if milestone_reached?(group.occurrence_count)
    ProjectErrorGroupNotificationJob.perform_later(group.id, "frequent_error", frequent_error_metadata) unless created
    group
  end

  private

  def derive_fingerprint
    @event.fingerprint.presence ||
      @event.message.to_s.lines.first.to_s.strip.presence ||
      @event.uuid
  end

  # find-or-create the ErrorGroup, then update counters atomically
  def upsert_group(fingerprint)
    group = @project.error_groups.find_or_initialize_by(fingerprint: fingerprint)

    created = group.new_record?

    regressed = false

    if created
      # Build initial state from the event
      ctx = @event.context.is_a?(Hash) ? @event.context : {}
      exc = ctx["exception"] || ctx[:exception]

      group.assign_attributes(
        title:           @event.message.to_s.lines.first.to_s.strip.presence || "Untitled error",
        subtitle:        exc.is_a?(Hash) ? (exc["class"].presence || exc[:class].presence) : nil,
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
      group.save!
    else
      regressed = !group.unresolved?
      group.record_occurrence!(@event)
    end

    # Back-link on the ingest_event row so we can JOIN cheaply
    @event.update_column(:error_group_id, group.id)

    [ group, created, regressed ]
  end

  def link_occurrence(group)
    ErrorOccurrence.find_or_create_by!(
      error_group:  group,
      ingest_event: @event
    ) do |occ|
      occ.occurred_at = @event.occurred_at
      occ.ingest_event_occurred_at = @event.occurred_at
    end
  end

  def milestone_reached?(count)
    count == 10 || count == 100 || count == 1_000 || (count > 1_000 && (count % 1_000).zero?)
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

  def frequent_error_metadata
    {
      "event_id" => @event.id,
      "event_uuid" => @event.uuid,
      "occurred_at" => @event.occurred_at.utc.iso8601,
      "bucket" => @event.occurred_at.utc.strftime("%Y%m%d%H")
    }
  end
end

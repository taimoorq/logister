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
    group       = upsert_group(fingerprint)
    link_occurrence(group)
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

    if group.new_record?
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
        occurrence_count: 1
      )
      group.save!
    else
      group.record_occurrence!(@event)
    end

    # Back-link on the ingest_event row so we can JOIN cheaply
    @event.update_column(:error_group_id, group.id)

    group
  end

  def link_occurrence(group)
    ErrorOccurrence.find_or_create_by!(
      error_group:  group,
      ingest_event: @event
    ) do |occ|
      occ.occurred_at = @event.occurred_at
    end
  end
end

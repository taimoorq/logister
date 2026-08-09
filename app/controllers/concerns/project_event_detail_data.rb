module ProjectEventDetailData
  extend ActiveSupport::Concern

  OCCURRENCE_PAGE_SIZE = 50

  OccurrencePage = Data.define(:items, :total_count, :next_cursor, :first_page) do
    include Enumerable

    def each(&block)
      items.each(&block)
    end

    def any?
      items.any?
    end

    def empty?
      items.empty?
    end

    def size
      total_count
    end
  end

  private

  def build_project_event_detail(project, event, group: nil, occurrence_scope: nil)
    resolved_group = group || event.error_group
    occurrences = if resolved_group
      scope = occurrence_scope || resolved_group.error_occurrences
      paginated_occurrences(scope.where(error_group_id: resolved_group.id))
    else
      OccurrencePage.new(items: [], total_count: 0, next_cursor: nil, first_page: true)
    end

    {
      event: event,
      group: resolved_group,
      occurrences: occurrences,
      related_logs: IngestEvent.related_logs(project: project, event: event, window: 5.minutes, limit: 50),
      impact_summary: resolved_group && ProjectExperience.for(project).supports?(:mobile) ? ErrorGroupImpactSummary.for_group(resolved_group, since: occurrence_scope ? nil : detail_impact_since, occurrence_scope: occurrence_scope) : nil
    }
  end

  def partitioned_occurrences(occurrences)
    events_by_id = IngestEvent.partition_reference_index(
      occurrences,
      id_key: :ingest_event_id,
      occurred_at_key: :ingest_event_occurred_at
    )

    occurrences.each do |occurrence|
      occurrence.ingest_event_record = events_by_id[occurrence.ingest_event_id]
    end
  end

  def paginated_occurrences(scope)
    ordered = scope.reorder(occurred_at: :desc, id: :desc)
    total_count = ordered.count
    cursor = params[:occurrence_cursor].to_s.presence
    first_page = cursor.blank?

    if cursor
      anchor = ordered.find_by(uuid: cursor)
      if anchor
        table = ErrorOccurrence.arel_table
        ordered = ordered.where(
          table[:occurred_at].lt(anchor.occurred_at).or(
            table[:occurred_at].eq(anchor.occurred_at).and(table[:id].lt(anchor.id))
          )
        )
      else
        first_page = true
      end
    end

    records = ordered.limit(OCCURRENCE_PAGE_SIZE + 1).to_a
    has_more = records.size > OCCURRENCE_PAGE_SIZE
    visible = records.first(OCCURRENCE_PAGE_SIZE)
    partitioned_occurrences(visible)

    OccurrencePage.new(
      items: visible,
      total_count:,
      next_cursor: has_more ? visible.last&.uuid : nil,
      first_page:
    )
  end

  def detail_impact_since
    range = params[:time_range].to_s
    return nil if range == "all"

    ({ "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days, "90d" => 90.days }[range] || 30.days).ago
  end
end

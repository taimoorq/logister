class ErrorDigestSummary
  Entry = Struct.new(:group, :occurrence_count, :latest_occurrence_at, keyword_init: true)

  attr_reader :project, :period_start, :period_end, :limit

  def initialize(project:, period_start:, period_end:, limit: 10)
    @project = project
    @period_start = period_start
    @period_end = period_end
    @limit = limit
  end

  def entries
    @entries ||= begin
      selected_groups.map do |group|
        Entry.new(
          group: group,
          occurrence_count: occurrence_counts.fetch(group.id, 0),
          latest_occurrence_at: latest_occurrences.fetch(group.id, group.last_seen_at)
        )
      end
    end
  end

  def total_occurrences
    occurrence_counts.values.sum
  end

  def error_group_count
    occurrence_counts.size
  end

  def new_group_count
    selected_groups.count do |group|
      group.first_seen_at.present? && group.first_seen_at >= period_start && group.first_seen_at < period_end
    end
  end

  def empty?
    total_occurrences.zero?
  end

  def metadata
    {
      "period_start_at" => period_start.utc.iso8601,
      "period_end_at" => period_end.utc.iso8601,
      "total_occurrences" => total_occurrences,
      "error_group_count" => error_group_count,
      "new_group_count" => new_group_count
    }
  end

  private

  def occurrence_scope
    ErrorOccurrence.joins(:error_group)
                   .where(error_groups: { project_id: project.id })
                   .where(occurred_at: period_start...period_end)
  end

  def occurrence_counts
    @occurrence_counts ||= occurrence_scope.group(:error_group_id).count
  end

  def latest_occurrences
    @latest_occurrences ||= occurrence_scope.group(:error_group_id).maximum(:occurred_at)
  end

  def selected_groups
    @selected_groups ||= begin
      ids = occurrence_counts
        .sort_by { |group_id, count| [ -count, -(latest_occurrences[group_id]&.to_i || 0) ] }
        .first(limit)
        .map(&:first)

      groups_by_id = project.error_groups.where(id: ids).includes(:latest_event).index_by(&:id)
      ids.filter_map { |id| groups_by_id[id] }
    end
  end
end

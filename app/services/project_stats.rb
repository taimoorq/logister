# frozen_string_literal: true

class ProjectStats
  def self.stats_for(project_ids)
    new(project_ids).stats_for
  end

  def self.latest_event_at_by_project(project_ids)
    ids = Array(project_ids).filter_map { |project_id| Integer(project_id, exception: false) }.uniq
    return {} if ids.blank?

    sql = Project.sanitize_sql_array([
      <<~SQL.squish,
        SELECT requested_projects.project_id, latest_events.occurred_at
        FROM unnest(ARRAY[?]::bigint[]) AS requested_projects(project_id)
        LEFT JOIN LATERAL (
          SELECT occurred_at
          FROM ingest_events
          WHERE ingest_events.project_id = requested_projects.project_id
          ORDER BY occurred_at DESC
          LIMIT 1
        ) latest_events ON TRUE
      SQL
      ids
    ])

    Project.connection.exec_query(sql).each_with_object({}) do |row, latest_events|
      occurred_at = row["occurred_at"]
      next if occurred_at.blank?

      latest_events[row["project_id"].to_i] = occurred_at
    end
  end

  def initialize(project_ids)
    @project_ids = Array(project_ids).compact
  end

  def stats_for
    return {} if project_ids.blank?

    stats = project_ids.index_with do
      { total_events: 0, activity_events: 0, open_groups: 0, all_groups: 0, latest_event_at: nil, trend: Array.new(7, 0) }
    end
    project_error_groups = ErrorGroup.where(project_id: project_ids)
    project_events = IngestEvent.where(project_id: project_ids)
    trend_dates = 7.times.map { |i| Date.current - (6 - i) }
    recent_events = project_events.where("occurred_at >= ?", trend_dates.first.beginning_of_day)

    apply_group_counts(stats, project_error_groups)
    apply_activity_counts(stats, recent_events)
    apply_latest_event_times(stats, recent_events)
    apply_event_trends(stats, recent_events, trend_dates)

    stats
  end

  private

  attr_reader :project_ids

  def apply_group_counts(stats, project_error_groups)
    project_error_groups.group(:project_id).count.each do |project_id, count|
      stats[project_id][:all_groups] = count
    end

    project_error_groups.unresolved.group(:project_id).count.each do |project_id, count|
      stats[project_id][:open_groups] = count
    end
  end

  def apply_activity_counts(stats, recent_events)
    activity_events = recent_events.where.not(event_type: IngestEvent.event_types[:error])
    activity_events.group(:project_id).count.each do |project_id, count|
      stats[project_id][:activity_events] = count
    end
  end

  def apply_latest_event_times(stats, recent_events)
    recent_events.group(:project_id).maximum(:occurred_at).each do |project_id, occurred_at|
      stats[project_id][:latest_event_at] = occurred_at
    end
  end

  def apply_event_trends(stats, recent_events, trend_dates)
    recent_events
      .group(:project_id, "DATE(occurred_at)")
      .count
      .each do |(project_id, date), count|
        idx = trend_dates.index(date.to_date)
        next unless idx

        stats[project_id][:trend][idx] = count
        stats[project_id][:total_events] += count
      end
  end
end

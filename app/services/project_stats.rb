# frozen_string_literal: true

class ProjectStats
  def self.stats_for(project_ids)
    new(project_ids).stats_for
  end

  def self.latest_event_at_by_project(project_ids)
    latest_timestamp_by_project(project_ids, :occurred_at)
  end

  def self.latest_received_at_by_project(project_ids)
    latest_timestamp_by_project(project_ids, :created_at)
  end

  def self.latest_timestamp_by_project(project_ids, column)
    raise ArgumentError unless %i[occurred_at created_at].include?(column)

    ids = Array(project_ids).filter_map { |project_id| Integer(project_id, exception: false) }.uniq
    return {} if ids.blank?

    sql = Project.sanitize_sql_array([
      <<~SQL.squish,
        SELECT requested_projects.project_id, latest_events.#{column}
        FROM unnest(ARRAY[?]::bigint[]) AS requested_projects(project_id)
        LEFT JOIN LATERAL (
          SELECT #{column}
          FROM ingest_events
          WHERE ingest_events.project_id = requested_projects.project_id
          ORDER BY #{column} DESC
          LIMIT 1
        ) latest_events ON TRUE
      SQL
      ids
    ])

    Project.connection.exec_query(sql).each_with_object({}) do |row, latest_events|
      occurred_at = row[column.to_s]
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
      {
        total_events: 0,
        activity_events: 0,
        received_events: 0,
        open_groups: 0,
        all_groups: 0,
        latest_event_at: nil,
        latest_received_at: nil,
        trend: Array.new(7, 0),
        receipt_trend: Array.new(7, 0)
      }
    end
    project_error_groups = ErrorGroup.where(project_id: project_ids)
    project_events = IngestEvent.where(project_id: project_ids)
    trend_dates = 7.times.map { |i| Date.current - (6 - i) }
    recent_events = project_events.where("occurred_at >= ?", trend_dates.first.beginning_of_day)
    recent_receipts = project_events.where("created_at >= ?", trend_dates.first.beginning_of_day)

    apply_group_counts(stats, project_error_groups)
    apply_event_stats(stats, recent_events, trend_dates)
    apply_receipt_stats(stats, recent_receipts, trend_dates)

    stats
  end

  private

  attr_reader :project_ids

  def apply_group_counts(stats, project_error_groups)
    project_error_groups.group(:project_id, :status).count.each do |(project_id, status), count|
      stats[project_id][:all_groups] += count
      stats[project_id][:open_groups] += count if status == "unresolved"
    end
  end

  def apply_event_stats(stats, recent_events, trend_dates)
    recent_events.group(:project_id, Arel.sql("DATE(occurred_at)"), :event_type)
      .pluck(:project_id, Arel.sql("DATE(occurred_at)"), :event_type, Arel.sql("COUNT(*)"), Arel.sql("MAX(occurred_at)"))
      .each do |project_id, date, event_type, count, latest_at|
        entry = stats.fetch(project_id)
        entry[:activity_events] += count unless event_type == "error"
        entry[:latest_event_at] = [ entry[:latest_event_at], latest_at ].compact.max
        index = trend_dates.index(date.to_date)
        next unless index

        entry[:trend][index] += count
        entry[:total_events] += count
      end
  end

  def apply_receipt_stats(stats, recent_receipts, trend_dates)
    self.class.latest_received_at_by_project(project_ids).each do |project_id, received_at|
      stats[project_id][:latest_received_at] = received_at
    end

    recent_receipts.group(:project_id, "DATE(created_at)").count.each do |(project_id, date), count|
      stats[project_id][:received_events] += count
      index = trend_dates.index(date.to_date)
      stats[project_id][:receipt_trend][index] = count if index
    end
  end
end

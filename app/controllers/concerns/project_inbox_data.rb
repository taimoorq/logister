require "digest"

module ProjectInboxData
  extend ActiveSupport::Concern

  INBOX_FILTERS = %w[unresolved introduced_today resolved ignored archived all].freeze
  INBOX_LIMIT = 100

  private

  # Returns error groups filtered by tab + query.
  def inbox_groups(project, filter:, query: nil)
    normalized_filter = filter.to_s.presence_in(INBOX_FILTERS) || "unresolved"
    normalized_query = query.to_s.strip.downcase

    cache_key = [
      "project",
      project.id,
      "inbox_groups",
      normalized_filter,
      Digest::SHA256.hexdigest(normalized_query),
      inbox_cache_version(project)
    ]

    group_ids = safe_cache_fetch(cache_key, expires_in: 20.seconds) do
      scope = base_inbox_scope(project, normalized_filter)
      scope = apply_inbox_query(scope, normalized_query) if normalized_query.present?
      scope.recent_first.limit(INBOX_LIMIT).pluck(:id)
    end

    return [] if group_ids.empty?

    groups_by_id = project.error_groups.where(id: group_ids).includes(:latest_event).index_by(&:id)
    group_ids.filter_map { |id| groups_by_id[id] }
  end

  def inbox_group_trends(project, groups, days: 7)
    group_ids = groups.map(&:id)
    return {} if group_ids.empty?

    cache_key = [
      "project",
      project.id,
      "inbox_group_trends",
      days,
      Digest::SHA256.hexdigest(group_ids.join(",")),
      inbox_cache_version(project)
    ]

    safe_cache_fetch(cache_key, expires_in: 20.seconds) do
      start_date = days.days.ago.to_date
      trend_dates = (0...days).map { |offset| start_date + offset }
      trends = group_ids.index_with { Array.new(days, 0) }

      ErrorOccurrence.where(error_group_id: group_ids)
                     .where("occurred_at >= ?", start_date.beginning_of_day)
                     .group(:error_group_id, "DATE(occurred_at)")
                     .count
                     .each do |(group_id, date), count|
        idx = trend_dates.index(date.to_date)
        trends[group_id][idx] = count if idx
      end

      trends
    end
  end

  # Per-status counts for the sidebar navigation.
  def inbox_counts(project)
    cache_key = [ "project", project.id, "inbox_counts", inbox_cache_version(project) ]
    safe_cache_fetch(cache_key, expires_in: 30.seconds) do
      groups = project.error_groups
      {
        unresolved:       groups.unresolved.count,
        introduced_today: groups.introduced_today.count,
        resolved:         groups.resolved.count,
        ignored:          groups.ignored.count,
        archived:         groups.archived.count,
        all:              groups.count
      }
    end
  end

  private

  def base_inbox_scope(project, filter)
    groups = project.error_groups
    case filter
    when "introduced_today" then groups.introduced_today
    when "resolved"         then groups.resolved
    when "ignored"          then groups.ignored
    when "archived"         then groups.archived
    when "all"              then groups
    else                         groups.unresolved
    end
  end

  def apply_inbox_query(scope, query)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    scope.where(
      "LOWER(title) LIKE :t OR LOWER(COALESCE(subtitle,'')) LIKE :t OR LOWER(fingerprint) LIKE :t OR LOWER(stage) LIKE :t",
      t: term
    )
  end

  def inbox_cache_version(project)
    project.error_groups.maximum(:updated_at)&.utc&.to_i || 0
  end
end

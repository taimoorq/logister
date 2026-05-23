require "digest"

module ProjectInboxData
  extend ActiveSupport::Concern

  INBOX_FILTERS = %w[unresolved introduced_today resolved ignored archived all].freeze
  INBOX_LIMIT = 100

  private

  # Returns error groups filtered by tab + assignment + query.
  def inbox_groups(project, filter:, query: nil, assignee: "all", viewer: nil)
    normalized_filter = filter.to_s.presence_in(INBOX_FILTERS) || "unresolved"
    normalized_query = query.to_s.strip.downcase
    normalized_assignee = normalize_inbox_assignee_filter(project, assignee, viewer: viewer)

    cache_key = [
      "project",
      project.id,
      "inbox_groups",
      normalized_filter,
      normalized_assignee,
      Digest::SHA256.hexdigest(normalized_query),
      inbox_cache_version(project)
    ]

    group_ids = safe_cache_fetch(cache_key, expires_in: 20.seconds) do
      scope = base_inbox_scope(project, normalized_filter)
      scope = apply_inbox_assignee(scope, project, normalized_assignee, viewer: viewer)
      scope = apply_inbox_query(scope, normalized_query) if normalized_query.present?
      scope.recent_first.limit(INBOX_LIMIT).pluck(:id)
    end

    return [] if group_ids.empty?

    groups_by_id = project.error_groups.where(id: group_ids).includes(:assignee).index_by(&:id)
    group_ids.filter_map { |id| groups_by_id[id] }
  end

  def inbox_latest_events(groups)
    latest_event_ids = groups.filter_map(&:latest_event_id)
    return {} if latest_event_ids.empty?

    IngestEvent.where(id: latest_event_ids)
               .select(:id, :project_id, :uuid)
               .index_by(&:id)
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
  def inbox_counts(project, assignee: "all", viewer: nil)
    normalized_assignee = normalize_inbox_assignee_filter(project, assignee, viewer: viewer)
    cache_key = [ "project", project.id, "inbox_counts", normalized_assignee, inbox_cache_version(project) ]
    safe_cache_fetch(cache_key, expires_in: 30.seconds) do
      groups = apply_inbox_assignee(project.error_groups, project, normalized_assignee, viewer: viewer)
      status_counts = groups.group(:status).count

      {
        unresolved:       inbox_status_count(status_counts, "unresolved"),
        introduced_today: groups.introduced_today.count,
        resolved:         inbox_status_count(status_counts, "resolved"),
        ignored:          inbox_status_count(status_counts, "ignored"),
        archived:         inbox_status_count(status_counts, "archived"),
        all:              status_counts.values.sum
      }
    end
  end

  def project_has_activity_events?(project)
    safe_cache_fetch(
      [ "project", project.id, "has_activity_events", cache_time_bucket(30.seconds) ],
      expires_in: 30.seconds
    ) do
      project.ingest_events.where.not(event_type: IngestEvent.event_types[:error]).exists?
    end
  end

  private

  def inbox_status_count(counts, status)
    counts[status].to_i + counts[status.to_sym].to_i + counts[ErrorGroup.statuses.fetch(status)].to_i
  end

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

  def normalize_inbox_assignee_filter(project, assignee, viewer: nil)
    user = inbox_viewer(viewer)
    raw = assignee.to_s.strip

    return "all" if raw.blank? || raw == "all"
    return "me" if raw == "me" && user.present?
    return "unassigned" if raw == "unassigned"
    return raw if project.assignable_users.exists?(uuid: raw)

    "all"
  end

  def apply_inbox_assignee(scope, project, assignee, viewer: nil)
    case assignee
    when "me"
      user = inbox_viewer(viewer)
      user.present? ? scope.assigned_to(user) : scope
    when "unassigned"
      scope.unassigned
    when "all"
      scope
    else
      assignable = project.assignable_users.find_by(uuid: assignee)
      assignable.present? ? scope.assigned_to(assignable) : scope
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

  def inbox_viewer(viewer)
    return viewer if viewer.present?
    return current_user if respond_to?(:current_user, true)

    nil
  end
end

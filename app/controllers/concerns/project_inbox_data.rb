module ProjectInboxData
  extend ActiveSupport::Concern

  INBOX_FILTERS = %w[unresolved introduced_today resolved ignored archived all].freeze

  private

  # Returns an ActiveRecord::Relation of ErrorGroups filtered by tab + query.
  def inbox_groups(project, filter:, query: nil)
    scope = base_inbox_scope(project, filter)
    scope = apply_inbox_query(scope, query) if query.present?
    scope.includes(:latest_event).recent_first
  end

  # Per-status counts for the sidebar navigation.
  def inbox_counts(project)
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
    term = "%#{sanitize_sql_like(query.downcase)}%"
    scope.where(
      "LOWER(title) LIKE :t OR LOWER(COALESCE(subtitle,'')) LIKE :t OR LOWER(fingerprint) LIKE :t OR LOWER(stage) LIKE :t",
      t: term
    )
  end

  # Safe LIKE-escape — available inside controllers via AR helper
  def sanitize_sql_like(str)
    str.gsub("\\", "\\\\\\\\").gsub("%", "\\%").gsub("_", "\\_")
  end
end

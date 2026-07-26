# frozen_string_literal: true

require "digest"

class ProjectInboxQuery
  FILTERS = %w[unresolved introduced_today resolved ignored archived all].freeze
  LIMIT = 100
  Page = Data.define(:groups, :next_cursor)

  MECHANISM_PRIORITY_SQL = <<~SQL.squish.freeze
    MAX(CASE error_occurrences.mechanism
      WHEN 'anr' THEN 5 WHEN 'native_crash' THEN 4 WHEN 'unhandled_exception' THEN 3
      WHEN 'low_memory_kill' THEN 2 WHEN 'handled_exception' THEN 1 ELSE 0 END)
  SQL
  VELOCITY_SQL = <<~SQL.squish.freeze
    (COUNT(error_occurrences.id) FILTER (
      WHERE error_occurrences.occurred_at >= CURRENT_DATE - INTERVAL '1 day'
    ) - COUNT(error_occurrences.id) FILTER (
      WHERE error_occurrences.occurred_at >= CURRENT_DATE - INTERVAL '2 days'
        AND error_occurrences.occurred_at < CURRENT_DATE - INTERVAL '1 day'
    ))
  SQL

  attr_reader :project, :viewer, :profile, :page_size

  def initialize(project:, viewer: nil, page_size: LIMIT)
    @project = project
    @viewer = viewer
    @profile = ProjectExperience.for(project)
    @page_size = page_size.to_i.clamp(1, LIMIT)
  end

  def groups(filter:, query: nil, assignee: "all", dimensions: {}, sort: nil, cursor: nil)
    page(filter: filter, query: query, assignee: assignee, dimensions: dimensions, sort: sort, cursor: cursor).groups
  end

  def page(filter:, query: nil, assignee: "all", dimensions: {}, sort: nil, cursor: nil)
    normalized_filter = filter.to_s.presence_in(FILTERS) || "unresolved"
    normalized_query = query.to_s.strip.downcase
    normalized_assignee = normalize_assignee(assignee)
    normalized_dimensions = normalize_dimensions(dimensions)
    normalized_sort = normalize_sort(sort)
    context_digest = cursor_context_digest(
      filter: normalized_filter,
      query: normalized_query,
      assignee: normalized_assignee,
      dimensions: normalized_dimensions,
      sort: normalized_sort
    )
    cursor_values = decode_cursor(cursor, context_digest:, sort: normalized_sort)

    cache_key = [
      "project",
      project.id,
      "inbox_groups",
      profile.key,
      profile.version,
      normalized_filter,
      normalized_assignee,
      normalized_sort,
      Digest::SHA256.hexdigest(normalized_query),
      Digest::SHA256.hexdigest(normalized_dimensions.to_json),
      Digest::SHA256.hexdigest(cursor.to_s),
      page_size,
      cache_version
    ]

    page_data = cache_fetch(cache_key, expires_in: 20.seconds) do
      scope = base_scope(normalized_filter)
      scope = apply_assignee(scope, normalized_assignee)
      scope = apply_query(scope, normalized_query) if normalized_query.present?
      scope = apply_dimensions(scope, normalized_dimensions)
      scope = apply_sort(scope, normalized_sort)
      scope = apply_cursor(scope, normalized_sort, cursor_values) if cursor_values
      ranked_groups = select_cursor_values(scope, normalized_sort).limit(page_size + 1).to_a
      has_more = ranked_groups.size > page_size
      visible_groups = ranked_groups.first(page_size)
      next_cursor = if has_more && visible_groups.last
        encode_cursor(context_digest:, sort: normalized_sort, values: cursor_values_for(visible_groups.last, normalized_sort))
      end

      [ visible_groups.map(&:id), next_cursor ]
    end

    group_ids, next_cursor = page_data

    return Page.new(groups: [], next_cursor: nil) if group_ids.empty?

    groups_by_id = project.error_groups.where(id: group_ids).includes(:assignee).index_by(&:id)
    Page.new(groups: group_ids.filter_map { |id| groups_by_id[id] }, next_cursor: next_cursor)
  end

  def latest_events(groups)
    IngestEvent.for_partition_references(
      groups,
      id_key: :latest_event_id,
      occurred_at_key: :latest_event_occurred_at
    ).select(:id, :project_id, :uuid, :occurred_at, :event_type, :level, :message, :context, :error_group_id).index_by(&:id)
  end

  def group_trends(groups, days: 7)
    group_ids = groups.map(&:id)
    return {} if group_ids.empty?

    key = [
      "project",
      project.id,
      "inbox_group_trends",
      profile.key,
      profile.version,
      days,
      Digest::SHA256.hexdigest(group_ids.join(",")),
      cache_version
    ]

    cache_fetch(key, expires_in: 20.seconds) do
      start_date = days.days.ago.to_date
      dates = (0...days).map { |offset| start_date + offset }
      trends = group_ids.index_with { Array.new(days, 0) }

      ErrorOccurrence.where(error_group_id: group_ids)
                     .where("occurred_at >= ?", start_date.beginning_of_day)
                     .group(:error_group_id, "DATE(occurred_at)")
                     .count
                     .each do |(group_id, date), count|
        index = dates.index(date.to_date)
        trends[group_id][index] = count if index
      end

      trends
    end
  end

  def counts(assignee: "all")
    normalized_assignee = normalize_assignee(assignee)
    key = [ "project", project.id, "inbox_counts", profile.key, profile.version, normalized_assignee, cache_version ]

    cache_fetch(key, expires_in: 30.seconds) do
      scope = apply_assignee(project.error_groups, normalized_assignee)
      status_counts = scope.group(:status).count

      {
        unresolved: status_count(status_counts, "unresolved"),
        introduced_today: scope.introduced_today.count,
        resolved: status_count(status_counts, "resolved"),
        ignored: status_count(status_counts, "ignored"),
        archived: status_count(status_counts, "archived"),
        all: status_counts.values.sum
      }
    end
  end

  def has_activity_events?
    cache_fetch(
      [ "project", project.id, "has_activity_events", profile.key, time_bucket(30.seconds) ],
      expires_in: 30.seconds
    ) do
      project.ingest_events.where.not(event_type: IngestEvent.event_types[:error]).exists?
    end
  end

  def filter_options
    return {} unless profile.supports?(:mobile) && ErrorOccurrence.column_names.include?("dimensions")

    key = [ "project", project.id, "inbox_filter_options", profile.key, profile.version, cache_version ]
    cache_fetch(key, expires_in: 1.minute) do
      scope = ErrorOccurrence.joins(:error_group).where(error_groups: { project_id: project.id })
      profile.filters.each_with_object({}) do |definition, values|
        next if definition.options.present?

        column = definition.key.to_s
        expression = column == "release" ? "error_occurrences.release" : "error_occurrences.dimensions ->> #{ActiveRecord::Base.connection.quote(column)}"
        values[column] = scope.where("COALESCE(#{expression}, '') <> ''").distinct.order(Arel.sql(expression)).pluck(Arel.sql(expression)).first(100)
      end
    end
  end

  def normalize_assignee(assignee)
    raw = assignee.to_s.strip
    return "all" if raw.blank? || raw == "all"
    return "me" if raw == "me" && viewer.present?
    return "unassigned" if raw == "unassigned"
    return raw if project.assignable_users.exists?(uuid: raw)

    "all"
  end

  private

  def base_scope(filter)
    scope = project.error_groups
    case filter
    when "introduced_today" then scope.introduced_today
    when "resolved" then scope.resolved
    when "ignored" then scope.ignored
    when "archived" then scope.archived
    when "all" then scope
    else scope.unresolved
    end
  end

  def apply_assignee(scope, assignee)
    case assignee
    when "me" then viewer.present? ? scope.assigned_to(viewer) : scope
    when "unassigned" then scope.unassigned
    when "all" then scope
    else
      assignable = project.assignable_users.find_by(uuid: assignee)
      assignable.present? ? scope.assigned_to(assignable) : scope
    end
  end

  def apply_query(scope, query)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    scope.where(
      "LOWER(title) LIKE :term OR LOWER(COALESCE(subtitle,'')) LIKE :term OR LOWER(fingerprint) LIKE :term OR LOWER(stage) LIKE :term",
      term: term
    )
  end

  def normalize_dimensions(dimensions)
    allowed_keys = profile.filters.map { |filter| filter.key.to_s }
    dimensions.to_h.stringify_keys.slice(*allowed_keys).transform_values { |value| value.to_s.strip }.compact_blank.sort.to_h
  end

  def apply_dimensions(scope, dimensions)
    return scope if dimensions.empty? || !ErrorOccurrence.column_names.include?("dimensions")

    occurrence_scope = ErrorOccurrence.where(error_group_id: scope.select(:id))
    dimensions.each do |key, value|
      if key == "time_range"
        duration = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days, "90d" => 90.days }[value]
        occurrence_scope = occurrence_scope.where("error_occurrences.occurred_at >= ?", duration.ago) if duration
      elsif key == "foreground"
        occurrence_scope = occurrence_scope.where(foreground: ActiveModel::Type::Boolean.new.cast(value))
      elsif key == "mechanism" && ErrorOccurrence.column_names.include?("mechanism")
        occurrence_scope = occurrence_scope.where(mechanism: value)
      elsif key == "release" && ErrorOccurrence.column_names.include?("release")
        occurrence_scope = occurrence_scope.where(release: value)
      else
        occurrence_scope = occurrence_scope.where("dimensions ->> ? = ?", key, value)
      end
    end

    scope.where(id: occurrence_scope.select(:error_group_id))
  end

  def normalize_sort(sort)
    allowed = profile.sort_options.map(&:last)
    sort.to_s.presence_in(allowed) || profile.default_sort
  end

  def apply_sort(scope, sort)
    return scope.recent_first unless ErrorOccurrence.column_names.include?("installation_hash")

    case sort
    when "impact"
      scope.left_joins(:error_occurrences)
           .group("error_groups.id")
           .order(Arel.sql("COUNT(DISTINCT error_occurrences.installation_hash) DESC NULLS LAST, error_groups.last_seen_at DESC, error_groups.id DESC"))
    when "recommended"
      scope.left_joins(:error_occurrences)
           .group("error_groups.id")
           .order(Arel.sql(<<~SQL.squish))
             #{MECHANISM_PRIORITY_SQL} DESC,
             error_groups.regression_count DESC,
             COUNT(DISTINCT error_occurrences.installation_hash) DESC NULLS LAST,
             error_groups.last_seen_at DESC,
             error_groups.id DESC
           SQL
    when "velocity"
      scope.left_joins(:error_occurrences)
           .group("error_groups.id")
           .order(Arel.sql("#{VELOCITY_SQL} DESC, error_groups.last_seen_at DESC, error_groups.id DESC"))
    else
      scope.recent_first
    end
  end

  def select_cursor_values(scope, sort)
    if sort == "recommended" && ErrorOccurrence.column_names.include?("installation_hash")
      scope.select(
        "error_groups.id",
        "#{MECHANISM_PRIORITY_SQL} AS inbox_cursor_priority",
        "COALESCE(error_groups.regression_count, 0) AS inbox_cursor_regressions",
        "COUNT(DISTINCT error_occurrences.installation_hash) AS inbox_cursor_installations",
        "COALESCE(EXTRACT(EPOCH FROM error_groups.last_seen_at), 0) AS inbox_cursor_last_seen"
      )
    elsif sort == "impact" && ErrorOccurrence.column_names.include?("installation_hash")
      scope.select(
        "error_groups.id",
        "COUNT(DISTINCT error_occurrences.installation_hash) AS inbox_cursor_installations",
        "COALESCE(EXTRACT(EPOCH FROM error_groups.last_seen_at), 0) AS inbox_cursor_last_seen"
      )
    elsif sort == "velocity" && ErrorOccurrence.column_names.include?("installation_hash")
      scope.select(
        "error_groups.id",
        "#{VELOCITY_SQL} AS inbox_cursor_velocity",
        "COALESCE(EXTRACT(EPOCH FROM error_groups.last_seen_at), 0) AS inbox_cursor_last_seen"
      )
    else
      scope.select(
        "error_groups.id",
        "COALESCE(EXTRACT(EPOCH FROM error_groups.last_seen_at), 0) AS inbox_cursor_last_seen"
      )
    end
  end

  def apply_cursor(scope, sort, values)
    if sort == "recommended" && values.size == 5
      scope.having(
        "(#{MECHANISM_PRIORITY_SQL}, COALESCE(error_groups.regression_count, 0), COUNT(DISTINCT error_occurrences.installation_hash), COALESCE(EXTRACT(EPOCH FROM error_groups.last_seen_at), 0), error_groups.id) < (?, ?, ?, ?, ?)",
        *values
      )
    elsif sort == "impact" && values.size == 3
      scope.having(
        "(COUNT(DISTINCT error_occurrences.installation_hash), COALESCE(EXTRACT(EPOCH FROM error_groups.last_seen_at), 0), error_groups.id) < (?, ?, ?)",
        *values
      )
    elsif sort == "velocity" && values.size == 3
      scope.having(
        "(#{VELOCITY_SQL}, COALESCE(EXTRACT(EPOCH FROM error_groups.last_seen_at), 0), error_groups.id) < (?, ?, ?)",
        *values
      )
    elsif values.size == 2
      scope.where(
        "(COALESCE(EXTRACT(EPOCH FROM error_groups.last_seen_at), 0), error_groups.id) < (?, ?)",
        *values
      )
    else
      scope
    end
  end

  def cursor_values_for(group, sort)
    if sort == "recommended" && group.has_attribute?(:inbox_cursor_priority)
      [
        group.inbox_cursor_priority.to_i,
        group.inbox_cursor_regressions.to_i,
        group.inbox_cursor_installations.to_i,
        group.inbox_cursor_last_seen.to_f,
        group.id
      ]
    elsif sort == "impact" && group.has_attribute?(:inbox_cursor_installations)
      [ group.inbox_cursor_installations.to_i, group.inbox_cursor_last_seen.to_f, group.id ]
    elsif sort == "velocity" && group.has_attribute?(:inbox_cursor_velocity)
      [ group.inbox_cursor_velocity.to_i, group.inbox_cursor_last_seen.to_f, group.id ]
    else
      [ group.inbox_cursor_last_seen.to_f, group.id ]
    end
  end

  def cursor_context_digest(filter:, query:, assignee:, dimensions:, sort:)
    Digest::SHA256.hexdigest([ project.uuid, profile.key, profile.version, Date.current, filter, query, assignee, dimensions, sort ].to_json)
  end

  def encode_cursor(context_digest:, sort:, values:)
    cursor_verifier.generate({ "context" => context_digest, "sort" => sort, "values" => values }, purpose: :project_inbox)
  end

  def decode_cursor(cursor, context_digest:, sort:)
    return if cursor.blank?

    payload = cursor_verifier.verified(cursor, purpose: :project_inbox)
    return unless payload.is_a?(Hash)
    return unless ActiveSupport::SecurityUtils.secure_compare(payload["context"].to_s, context_digest)
    return unless payload["sort"] == sort && payload["values"].is_a?(Array)

    return unless payload["values"].all? { |value| value.is_a?(Numeric) }

    payload["values"]
  rescue ArgumentError, TypeError
    nil
  end

  def cursor_verifier
    Rails.application.message_verifier(:project_inbox_cursor)
  end

  def status_count(counts, status)
    counts[status].to_i + counts[status.to_sym].to_i + counts[ErrorGroup.statuses.fetch(status)].to_i
  end

  def cache_version
    project.error_groups.maximum(:updated_at)&.utc&.to_i || 0
  end

  def cache_fetch(key, expires_in:, &block)
    Rails.cache.fetch(key, expires_in: expires_in, race_condition_ttl: 5.seconds, &block)
  rescue StandardError => error
    Rails.logger.warn("cache fetch failed key=#{key.inspect}: #{error.class} #{error.message}")
    block.call
  end

  def time_bucket(duration)
    Time.current.to_i / duration.to_i
  end
end

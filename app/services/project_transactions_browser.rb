# frozen_string_literal: true

class ProjectTransactionsBrowser
  include TableCursorPagination

  PERIODS = {
    "24h" => 24.hours,
    "7d" => 7.days,
    "30d" => 30.days,
    "90d" => 90.days,
    "all" => nil
  }.freeze
  STATUSES = %w[all ok errored].freeze
  PER_PAGE_OPTIONS = [ 25, 50, 100 ].freeze
  ERROR_LEVELS = %w[error fatal].freeze
  NUMERIC_PATTERN = "^[0-9]+(\\.[0-9]+)?$"
  STATUS_PATTERN = "^[0-9]+$"
  TRANSACTION_NAME_SQL = <<~SQL.squish
    COALESCE(
      NULLIF(ingest_events.context->>'transaction_name', ''),
      NULLIF(ingest_events.context->>'transactionName', '')
    )
  SQL
  TRANSACTION_DURATION_SQL = <<~SQL.squish
    COALESCE(
      NULLIF(ingest_events.context->>'duration_ms', ''),
      NULLIF(ingest_events.context->>'durationMs', '')
    )
  SQL

  def initialize(project:, params:)
    @project = project
    @params = params
  end

  attr_reader :project, :params

  def frame_params
    permitted_params(:period, :status, :q, :min_duration_ms, :environment, :release, :per_page, :before, :after)
  end

  def filters
    @filters ||= {
      period: params[:period].presence_in(PERIODS.keys) || "24h",
      status: params[:status].presence_in(STATUSES) || "all",
      q: params[:q].to_s.strip,
      min_duration_ms: normalized_duration_filter(params[:min_duration_ms]),
      environment: params[:environment].to_s.strip,
      release: params[:release].to_s.strip,
      per_page: normalized_per_page(params[:per_page].presence || TableCursorPagination::DEFAULT_PER_PAGE)
    }
  end

  def filters_active?
    filters[:period] != "24h" ||
      filters[:status] != "all" ||
      filters[:q].present? ||
      filters[:min_duration_ms].present? ||
      filters[:environment].present? ||
      filters[:release].present?
  end

  def period_options
    [
      [ "24 hours", "24h" ],
      [ "7 days", "7d" ],
      [ "30 days", "30d" ],
      [ "90 days", "90d" ],
      [ "All time", "all" ]
    ]
  end

  def status_options
    [
      [ "All statuses", "all" ],
      [ "OK", "ok" ],
      [ "Errored", "errored" ]
    ]
  end

  def per_page_options
    PER_PAGE_OPTIONS
  end

  def page
    @page ||= cursor_page(
      filtered_transactions,
      before: params[:before],
      after: params[:after],
      per_page: filters[:per_page]
    )
  end

  def rows
    @rows ||= transaction_table_rows(page.records)
  end

  private

  def permitted_params(*keys)
    if params.respond_to?(:permit)
      params.permit(*keys).to_h.compact_blank
    else
      params.to_h.slice(*keys.map(&:to_s)).compact_blank
    end
  end

  def filtered_transactions
    scope = project.ingest_events.transactions
    scope = apply_period_filter(scope, filters[:period])
    scope = apply_text_filter(scope, filters[:q]) if filters[:q].present?
    scope = apply_status_filter(scope, filters[:status])
    scope = apply_min_duration_filter(scope, filters[:min_duration_ms]) if filters[:min_duration_ms].present?
    scope = scope.where("COALESCE(NULLIF(ingest_events.context->>'environment', ''), 'production') = ?", filters[:environment]) if filters[:environment].present?
    scope = scope.where("ingest_events.context->>'release' = ?", filters[:release]) if filters[:release].present?
    scope
  end

  def normalized_duration_filter(value)
    raw = value.to_s.strip
    return "" if raw.blank?

    raw.match?(/\A[0-9]+(\.[0-9]+)?\z/) ? raw : ""
  end

  def apply_period_filter(scope, period)
    lookback = PERIODS.fetch(period)
    return scope if lookback.blank?

    scope.where("ingest_events.occurred_at >= ?", lookback.ago)
  end

  def apply_text_filter(scope, query)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    condition_sql = [
      "LOWER(COALESCE(",
      TRANSACTION_NAME_SQL,
      ", ingest_events.message)) LIKE :term OR LOWER(ingest_events.message) LIKE :term"
    ].join

    scope.where(condition_sql, term: term)
  end

  def apply_status_filter(scope, status)
    case status
    when "errored"
      scope.where(errored_status_sql, levels: ERROR_LEVELS, status_pattern: STATUS_PATTERN)
    when "ok"
      scope.where("COALESCE(ingest_events.level, '') NOT IN (?)", ERROR_LEVELS)
           .where(ok_status_sql, status_pattern: STATUS_PATTERN)
    else
      scope
    end
  end

  def errored_status_sql
    <<~SQL.squish
      COALESCE(ingest_events.level, '') IN (:levels)
      OR (
        ingest_events.context->>'status' ~ :status_pattern
        AND (ingest_events.context->>'status')::integer >= 500
      )
    SQL
  end

  def ok_status_sql
    <<~SQL.squish
      ingest_events.context->>'status' IS NULL
      OR ingest_events.context->>'status' !~ :status_pattern
      OR (ingest_events.context->>'status')::integer < 500
    SQL
  end

  def apply_min_duration_filter(scope, minimum)
    condition_sql = [
      "(",
      TRANSACTION_DURATION_SQL,
      ") ~ :numeric_pattern AND (",
      TRANSACTION_DURATION_SQL,
      ")::numeric >= :minimum"
    ].join

    scope.where(condition_sql, numeric_pattern: NUMERIC_PATTERN, minimum: minimum.to_f)
  end

  def transaction_table_rows(events)
    error_summaries = transaction_error_summaries(events)

    events.map do |event|
      raw_name = IngestEvent.transaction_name(event).to_s
      summary = error_summaries.fetch(raw_name, {})
      {
        event: event,
        transaction_name: raw_name.presence || event.message.presence || "(unnamed transaction)",
        duration_ms: IngestEvent.duration_ms(event).round(2),
        status: transaction_status(event),
        related_error_count: summary.fetch(:count, 0),
        related_error_event: summary[:event]
      }
    end
  end

  def transaction_error_summaries(events)
    names = events.filter_map { |event| IngestEvent.transaction_name(event).to_s.presence }.uniq
    return {} if names.empty?

    scope = project.ingest_events.where(event_type: :error).where(transaction_name_node.in(names))
    scope = apply_period_filter(scope, filters[:period])
    scope = scope.where("COALESCE(NULLIF(ingest_events.context->>'environment', ''), 'production') = ?", filters[:environment]) if filters[:environment].present?
    scope = scope.where("ingest_events.context->>'release' = ?", filters[:release]) if filters[:release].present?

    counts = scope.group(transaction_name_node).count
    latest_events = scope
                    .select(Arel.sql([ "DISTINCT ON (", TRANSACTION_NAME_SQL, ") ingest_events.*" ].join))
                    .order(Arel.sql([ TRANSACTION_NAME_SQL, "ASC, ingest_events.occurred_at DESC, ingest_events.id DESC" ].join(" ")))
                    .to_a
                    .index_by { |event| IngestEvent.transaction_name(event).to_s }

    names.index_with do |name|
      { count: counts.fetch(name, 0), event: latest_events[name] }
    end
  end

  def transaction_name_node
    Arel.sql(TRANSACTION_NAME_SQL)
  end

  def transaction_status(event)
    context = event.context.is_a?(Hash) ? event.context : {}
    status = context["status"].presence || context[:status].presence
    numeric_status = status.to_s.match?(/\A[0-9]+\z/) ? status.to_i : nil
    errored = event.level.to_s.in?(ERROR_LEVELS) || numeric_status.to_i >= 500

    if numeric_status.present?
      "#{numeric_status} #{errored ? 'error' : 'ok'}"
    else
      errored ? "error" : "ok"
    end
  end
end

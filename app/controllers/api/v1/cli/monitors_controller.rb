# frozen_string_literal: true

class Api::V1::Cli::MonitorsController < Api::V1::Cli::BaseController
  CURSOR_RESOURCE = "monitors"
  SEARCH_LIMIT = 200
  STATUS_VALUES = %w[ok error missed paused].freeze

  before_action -> { require_cli_scopes!("monitors:read") }

  def index
    generated_at = Time.current
    filters = normalized_filters
    limit = cli_limit
    cursor = decode_cli_cursor(
      params[:cursor],
      resource: CURSOR_RESOURCE,
      project_uuid: cli_project.uuid,
      filters:
    )
    scope = filtered_scope(filters, at: generated_at)
    scope = scope.where("(check_in_monitors.updated_at, check_in_monitors.uuid) < (?, ?::uuid)", cursor[:timestamp], cursor[:uuid]) if cursor
    records = scope.order(updated_at: :desc, uuid: :desc).limit(limit + 1).to_a
    has_more = records.length > limit
    records = records.first(limit)
    events = Logister::CliEventQuery.summary(
      IngestEvent.for_partition_references(
        records,
        id_key: :last_event_id,
        occurred_at_key: :last_event_occurred_at
      )
    ).index_by(&:id)
    next_cursor = if has_more && records.last
      encode_cli_cursor(
        resource: CURSOR_RESOURCE,
        project_uuid: cli_project.uuid,
        filters:,
        timestamp: records.last.updated_at,
        uuid: records.last.uuid
      )
    end

    render json: cli_list_payload(
      items: records.map { |monitor| Logister::CliSerializer.monitor(monitor, at: generated_at, last_event: events[monitor.last_event_id]) },
      next_cursor:,
      generated_at:
    )
  end

  def show
    generated_at = Time.current
    monitor = cli_project.check_in_monitors.find_by!(uuid: params[:uuid])
    last_event = Logister::CliEventQuery.summary(
      IngestEvent.for_partition_references(
        [ monitor ],
        id_key: :last_event_id,
        occurred_at_key: :last_event_occurred_at
      )
    ).first
    render json: Logister::CliSerializer.monitor(monitor, at: generated_at, last_event:)
  end

  private

  def normalized_filters
    {
      environment: Logister::CliQuery.text(params[:environment].presence || params[:env], parameter: "environment", max: 100),
      status: Logister::CliQuery.enum(params[:status], parameter: "status", allowed: STATUS_VALUES, allow_all: true),
      q: Logister::CliQuery.text(params[:q].presence || params[:query], parameter: "q", max: SEARCH_LIMIT)
    }.compact
  end

  def filtered_scope(filters, at:)
    scope = cli_project.check_in_monitors
    scope = scope.where(environment: filters[:environment]) if filters[:environment].present?
    scope = apply_status_filter(scope, filters[:status], at:) if filters[:status].present? && filters[:status] != "all"
    scope = apply_text_filter(scope, filters[:q]) if filters[:q].present?
    scope
  end

  def apply_status_filter(scope, status, at:)
    active = scope.where(monitoring_paused_at: nil)
    deadline_sql = <<~SQL.squish
      check_in_monitors.last_check_in_at + make_interval(
        secs => check_in_monitors.expected_interval_seconds +
          GREATEST((check_in_monitors.expected_interval_seconds / 2), 30)
      )
    SQL

    case status
    when "paused"
      scope.where.not(monitoring_paused_at: nil)
    when "error"
      active.where(last_status: "error")
    when "missed"
      active.where.not(last_status: "error").where("last_check_in_at IS NULL OR #{deadline_sql} < ?", at)
    when "ok"
      active.where.not(last_status: "error").where("last_check_in_at IS NOT NULL AND #{deadline_sql} >= ?", at)
    end
  end

  def apply_text_filter(scope, query)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    scope.where("LOWER(check_in_monitors.slug) LIKE :term", term:)
  end
end

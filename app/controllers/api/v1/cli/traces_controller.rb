# frozen_string_literal: true

class Api::V1::Cli::TracesController < Api::V1::Cli::BaseController
  CURSOR_RESOURCE = "traces"
  STATUS_VALUES = %w[unset ok error].freeze
  TEXT_LIMIT = 200

  before_action -> { require_cli_scopes!("traces:read") }

  def index
    since_at, until_at = cli_time_range
    filters = normalized_filters
    cursor_filters = filters.merge(since: params[:since].to_s, until: params[:until].to_s)
    cursor = decode_cli_cursor(
      params[:cursor],
      resource: CURSOR_RESOURCE,
      project_uuid: cli_project.uuid,
      filters: cursor_filters
    )
    limit = cli_limit
    result = Logister::CliTracesQuery.list(
      project: cli_project,
      since: since_at,
      to: until_at,
      filters:,
      cursor:,
      limit:
    )
    has_more = result.items.length > limit
    items = result.items.first(limit)
    next_cursor = if has_more && items.last
      encode_cli_cursor(
        resource: CURSOR_RESOURCE,
        project_uuid: cli_project.uuid,
        filters: cursor_filters,
        timestamp: Time.zone.iso8601(items.last.fetch(:started_at)),
        uuid: items.last.fetch(:uuid)
      )
    end

    render json: cli_list_payload(
      items:,
      next_cursor:,
      analytics: Logister::CliSerializer.analytics(result.read)
    )
  end

  def show
    trace_id = Logister::CliQuery.text(params[:trace_id], parameter: "trace_id", max: 128)
    unless trace_id&.match?(/\A[A-Za-z0-9._:-]+\z/)
      raise Logister::CliQuery::InvalidParameter.new("trace_id contains unsupported characters", parameter: "trace_id")
    end
    since_at, until_at = cli_time_range
    result = Logister::CliTracesQuery.trace(project: cli_project, trace_id:, since: since_at, to: until_at)
    raise ActiveRecord::RecordNotFound if result.items.empty?

    render json: {
      trace_id:,
      spans: result.items,
      span_count: result.items.length,
      truncated: result.truncated,
      generated_at: Logister::CliSerializer.timestamp(Time.current),
      analytics: Logister::CliSerializer.analytics(result.read)
    }
  end

  private

  def normalized_filters
    {
      environment: Logister::CliQuery.text(params[:environment].presence || params[:env], parameter: "environment", max: 100),
      release: Logister::CliQuery.text(params[:release], parameter: "release", max: TEXT_LIMIT),
      service: Logister::CliQuery.text(params[:service], parameter: "service", max: TEXT_LIMIT),
      operation: Logister::CliQuery.text(params[:operation], parameter: "operation", max: TEXT_LIMIT),
      q: Logister::CliQuery.text(params[:q].presence || params[:query], parameter: "q", max: TEXT_LIMIT),
      status: Logister::CliQuery.enum(params[:status]&.downcase, parameter: "status", allowed: STATUS_VALUES, allow_all: true).presence_in(STATUS_VALUES),
      min_duration_ms: Logister::CliQuery.decimal(params[:min_duration_ms], parameter: "min_duration_ms", min: 0, max: 86_400_000)
    }.compact
  end
end

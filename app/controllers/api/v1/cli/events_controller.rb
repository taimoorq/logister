# frozen_string_literal: true

class Api::V1::Cli::EventsController < Api::V1::Cli::BaseController
  LIST_CURSOR_RESOURCE = "events"
  POLL_CURSOR_RESOURCE = "events_poll"
  ZERO_UUID = "00000000-0000-0000-0000-000000000000"
  LIST_ITEMS_BYTES_LIMIT = 900.kilobytes
  MAX_LIST_STRING_BYTES = 4.kilobytes

  before_action -> { require_cli_scopes!("events:read") }

  def index
    time_range = cli_time_range
    filters = event_cursor_filters
    base_scope = apply_event_common_filters(cli_project.ingest_events, time_range:)
    limit = cli_limit

    if params[:after_cursor].present?
      render_poll_page(base_scope, filters:, limit:)
    else
      render_list_page(base_scope, filters:, limit:, seed_timestamp: time_range.first)
    end
  end

  def show
    event = Logister::CliEventQuery.bounded_context(cli_project.ingest_events.where(uuid: params[:uuid]))
                                   .includes(:error_group)
                                   .first!

    render json: Logister::CliSerializer.event(event, include_context: true)
  end

  private

  def include_context?
    ActiveModel::Type::Boolean.new.cast(params[:include_context]) || params[:summary].to_s == "false"
  end

  def render_list_page(base_scope, filters:, limit:, seed_timestamp:)
    cursor = decode_cli_cursor(
      params[:cursor],
      resource: LIST_CURSOR_RESOURCE,
      project_uuid: cli_project.uuid,
      filters:
    )
    high_water = base_scope.reorder(created_at: :desc, uuid: :desc).select(:created_at, :uuid).first
    scope = base_scope
    scope = scope.where("(ingest_events.occurred_at, ingest_events.uuid) < (?, ?::uuid)", cursor[:timestamp], cursor[:uuid]) if cursor
    records = projected_event_scope(scope).includes(:error_group).order(occurred_at: :desc, uuid: :desc).limit(limit + 1).to_a
    has_more = records.length > limit
    records = records.first(limit)
    next_cursor = if has_more && records.last
      event_cursor(LIST_CURSOR_RESOURCE, filters, records.last.occurred_at, records.last.uuid)
    end
    poll_cursor = event_cursor(
      POLL_CURSOR_RESOURCE,
      filters,
      high_water&.created_at || seed_timestamp,
      high_water&.uuid || ZERO_UUID
    )

    render json: cli_list_payload(
      items: serialize_list_items(records),
      next_cursor:,
      poll_cursor:
    )
  end

  def render_poll_page(base_scope, filters:, limit:)
    cursor = decode_cli_cursor(
      params[:after_cursor],
      resource: POLL_CURSOR_RESOURCE,
      project_uuid: cli_project.uuid,
      filters:
    )
    scope = base_scope.where("(ingest_events.created_at, ingest_events.uuid) > (?, ?::uuid)", cursor[:timestamp], cursor[:uuid])
    records = projected_event_scope(scope).includes(:error_group).order(created_at: :asc, uuid: :asc).limit(limit + 1).to_a
    records = records.first(limit)
    high_water = records.last
    poll_cursor = if high_water
      event_cursor(POLL_CURSOR_RESOURCE, filters, high_water.created_at, high_water.uuid)
    else
      params[:after_cursor]
    end

    render json: cli_list_payload(
      items: serialize_list_items(records),
      next_cursor: poll_cursor,
      poll_cursor:
    )
  end

  def event_cursor(resource, filters, timestamp, uuid)
    encode_cli_cursor(resource:, project_uuid: cli_project.uuid, filters:, timestamp:, uuid:)
  end

  def projected_event_scope(scope)
    include_context? ? Logister::CliEventQuery.bounded_context(scope) : Logister::CliEventQuery.summary(scope)
  end

  def serialize_list_items(records)
    return [] if records.empty?

    max_item_bytes = (LIST_ITEMS_BYTES_LIMIT - 2) / records.length
    records.map do |event|
      item = Logister::CliSerializer.event(event, include_context: include_context?)
      bound_event_list_item(item, max_bytes: max_item_bytes)
    end
  end

  def bound_event_list_item(item, max_bytes:)
    return item if JSON.generate(item).bytesize <= max_bytes

    context_present = item.key?(:context) || item.key?("context")
    bounded = item.except(:context, "context")
    bounded[:context_truncated] = true if context_present
    return bounded if JSON.generate(bounded).bytesize <= max_bytes

    truncated = false
    bounded = bounded.transform_values do |value|
      next value unless value.is_a?(String) && value.bytesize > MAX_LIST_STRING_BYTES

      truncated = true
      "#{value.byteslice(0, MAX_LIST_STRING_BYTES).to_s.scrub}…"
    end
    bounded[:summary_truncated] = true if truncated
    return bounded if JSON.generate(bounded).bytesize <= max_bytes

    minimal = bounded.slice(:uuid, :event_type, :level, :occurred_at, :created_at, :error_group_uuid)
                     .merge(summary_truncated: true)
    minimal[:context_truncated] = true if context_present
    minimal
  end

  def event_cursor_filters
    {
      type: (params[:event_type].presence || params[:type]).to_s.split(",").map(&:strip).reject(&:blank?).sort,
      level: params[:level].to_s.split(",").map(&:strip).reject(&:blank?).sort,
      since: params[:since].to_s,
      until: params[:until].to_s,
      environment: (params[:environment].presence || params[:env]).to_s.strip,
      release: params[:release].to_s.strip,
      trace_id: params[:trace_id].to_s.strip,
      request_id: params[:request_id].to_s.strip,
      status: params[:status].to_s.strip.downcase,
      min_duration_ms: params[:min_duration_ms].to_s.strip,
      q: (params[:q].presence || params[:query]).to_s.strip
    }
  end
end

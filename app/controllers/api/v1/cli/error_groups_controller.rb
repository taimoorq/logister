# frozen_string_literal: true

class Api::V1::Cli::ErrorGroupsController < Api::V1::Cli::BaseController
  before_action -> { require_cli_scopes!("errors:read") }, except: :context
  before_action -> { require_cli_scopes!("errors:read", "ai_context:read") }, only: :context

  def index
    filter = issue_filter
    query = ProjectInboxQuery.new(
      project: cli_project,
      viewer: current_cli_access_token.user,
      page_size: cli_limit,
      strict_cursor: true
    )
    page = query.page(
      filter:,
      query: Logister::CliQuery.text(params[:q].presence || params[:query], parameter: "q", max: 200),
      assignee: issue_assignee,
      sort: issue_sort,
      cursor: params[:cursor]
    )
    latest_events = query.latest_events(page.groups)

    render json: cli_list_payload(
      items: page.groups.map { |group| Logister::CliSerializer.error_group(group, latest_event: latest_events[group.latest_event_id]) },
      next_cursor: page.next_cursor
    )
  end

  def show
    group = error_group
    latest_event = cli_latest_event(group)
    payload = {
      error_group: Logister::CliSerializer.error_group(group, latest_event: latest_event),
      occurrence_summary: Logister::CliSerializer.occurrence_summary(group)
    }
    if ActiveModel::Type::Boolean.new.cast(params[:related_logs]) && latest_event
      payload[:related_logs] = IngestEvent.related_logs(project: cli_project, event: latest_event, limit: 50) do |scope|
        Logister::CliEventQuery.summary(scope)
      end
                                            .map { |event| Logister::CliSerializer.event(event, include_context: false) }
    end

    render json: payload
  end

  def export
    render json: Logister::TelemetryRedactor.call(
      ErrorGroupJsonExporter.call(
        project: cli_project,
        group: error_group,
        include_occurrences: ActiveModel::Type::Boolean.new.cast(params[:include_occurrences]),
        logister_url: nil
      )
    )
  end

  def context
    render json: Logister::ErrorGroupAiContext.call(
      project: cli_project,
      group: error_group,
      logister_url: nil,
      token_budget: params[:token_budget]
    )
  end

  private

  def cli_latest_event(group)
    Logister::CliEventQuery.summary(
      IngestEvent.for_partition_references(
        [ group ],
        id_key: :latest_event_id,
        occurred_at_key: :latest_event_occurred_at
      )
    ).first
  end

  def error_group
    @error_group ||= cli_project.error_groups.find_by!(uuid: params[:uuid] || params[:error_group_uuid])
  end

  def issue_filter
    return "introduced_today" if ActiveModel::Type::Boolean.new.cast(params[:introduced_today])

    Logister::CliQuery.enum(
      params[:status].presence || "unresolved",
      parameter: "status",
      allowed: ProjectInboxQuery::FILTERS
    )
  end

  def issue_assignee
    raw = params[:assignee].presence || params[:assigned].presence || "all"
    normalized = {
      "any" => "assigned",
      "true" => "assigned",
      "false" => "all"
    }.fetch(raw.to_s.strip, raw.to_s.strip)
    return normalized if normalized.in?(%w[all me unassigned assigned])
    if Logister::TelemetryIdentity.valid_uuid?(normalized) && cli_project.assignable_users.exists?(uuid: normalized)
      return normalized
    end

    raise Logister::CliQuery::InvalidParameter.new(
      "assignee must be all, me, unassigned, any, or an assignable user UUID",
      parameter: "assignee"
    )
  end

  def issue_sort
    return if params[:sort].blank?

    allowed = ProjectExperience.for(cli_project).sort_options.map(&:last)
    Logister::CliQuery.enum(params[:sort], parameter: "sort", allowed:)
  end
end

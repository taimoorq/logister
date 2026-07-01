# frozen_string_literal: true

class Api::V1::Cli::ErrorGroupsController < Api::V1::Cli::BaseController
  before_action -> { require_cli_scopes!("errors:read") }, except: :context
  before_action -> { require_cli_scopes!("errors:read", "ai_context:read") }, only: :context

  def index
    groups = filtered_groups.includes(:assignee).order(last_seen_at: :desc, id: :desc).limit(cli_limit)
    latest_events = IngestEvent.for_partition_references(
      groups,
      id_key: :latest_event_id,
      occurred_at_key: :latest_event_occurred_at
    ).index_by(&:id)

    render json: {
      items: groups.map { |group| Logister::CliSerializer.error_group(group, latest_event: latest_events[group.latest_event_id]) }
    }
  end

  def show
    group = error_group
    latest_event = group.latest_event_record
    payload = {
      error_group: Logister::CliSerializer.error_group(group, latest_event: latest_event),
      occurrence_summary: Logister::CliSerializer.occurrence_summary(group)
    }
    if ActiveModel::Type::Boolean.new.cast(params[:related_logs]) && latest_event
      payload[:related_logs] = IngestEvent.related_logs(project: cli_project, event: latest_event, limit: 50)
                                            .map { |event| Logister::CliSerializer.event(event, include_context: true) }
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

  def error_group
    @error_group ||= cli_project.error_groups.find_by!(uuid: params[:uuid] || params[:error_group_uuid])
  end

  def filtered_groups
    groups = cli_project.error_groups
    status = params[:status].to_s.presence
    groups = groups.where(status: status) if status.present? && status != "all" && ErrorGroup.statuses.key?(status)
    groups = groups.where("first_seen_at >= ?", Time.current.beginning_of_day) if ActiveModel::Type::Boolean.new.cast(params[:introduced_today])
    groups = apply_group_text_filter(groups, params[:q].presence || params[:query].presence)
    groups
  end

  def apply_group_text_filter(scope, query)
    return scope if query.blank?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    scope.where(
      "LOWER(title) LIKE :term OR LOWER(COALESCE(subtitle, '')) LIKE :term OR LOWER(fingerprint) LIKE :term OR LOWER(stage) LIKE :term",
      term: term
    )
  end
end

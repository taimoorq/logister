# frozen_string_literal: true

class Api::V1::Cli::ProjectSummariesController < Api::V1::Cli::BaseController
  before_action -> { require_cli_scopes!("projects:read", "project_summary:read") }

  def show
    project = cli_project
    since = cli_since(default: 24.hours.ago)
    events = project.ingest_events.where("occurred_at >= ?", since)
    latest_event = project.ingest_events.order(occurred_at: :desc, id: :desc).select(:id, :uuid, :event_type, :level, :message, :fingerprint, :occurred_at, :created_at, :context, :error_group_id).first
    status_counts = project.error_groups.group(:status).count

    render json: {
      project: Logister::CliSerializer.project(project),
      window_started_at: Logister::CliSerializer.timestamp(since),
      generated_at: Time.current.utc.iso8601(6),
      latest_event: latest_event && Logister::CliSerializer.event(latest_event, include_context: false),
      events_by_type: event_type_counts(events),
      errors: {
        unresolved: count_status(status_counts, "unresolved"),
        resolved: count_status(status_counts, "resolved"),
        ignored: count_status(status_counts, "ignored"),
        archived: count_status(status_counts, "archived"),
        all: status_counts.values.sum
      },
      activity_events: events.where.not(event_type: :error).count
    }
  end

  private

  def event_type_counts(scope)
    counts = scope.group(:event_type).count
    IngestEvent.event_types.keys.index_with do |event_type|
      counts[event_type].to_i + counts[IngestEvent.event_types.fetch(event_type)].to_i
    end
  end

  def count_status(counts, status)
    counts[status].to_i + counts[status.to_sym].to_i + counts[ErrorGroup.statuses.fetch(status)].to_i
  end
end

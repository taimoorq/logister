# frozen_string_literal: true

class Api::V1::Cli::ProjectSummariesController < Api::V1::Cli::BaseController
  before_action -> { require_cli_scopes!("projects:read", "project_summary:read") }

  def show
    project = cli_project
    since, window_ended_at = cli_time_range
    generated_at = Time.current
    events = project.ingest_events.where(occurred_at: since...window_ended_at)
    read = Logister::ClickhouseReadRouter.call(
      project_ids: [ project.id ],
      signals: Logister::ClickhouseCoverage::EVENT_SIGNALS,
      from: since,
      to: window_ended_at,
      clickhouse: ->(client) {
        Logister::ClickhouseEventRollup.call(project_ids: [ project.id ], since:, to: window_ended_at, client:)
      },
      postgres: -> { postgres_rollup(events, project.id) }
    )
    latest_event = Logister::CliEventQuery.summary(events.order(occurred_at: :desc, id: :desc)).first
    status_counts = project.error_groups.group(:status).count
    events_by_type = event_type_counts(read.payload.fetch(:event_type_counts))

    render json: {
      project: Logister::CliSerializer.project(project),
      window_started_at: Logister::CliSerializer.timestamp(since),
      window_ended_at: Logister::CliSerializer.timestamp(window_ended_at),
      generated_at: Logister::CliSerializer.timestamp(generated_at),
      latest_event: latest_event && Logister::CliSerializer.event(latest_event, include_context: false),
      events_by_type: events_by_type,
      errors: {
        unresolved: count_status(status_counts, "unresolved"),
        resolved: count_status(status_counts, "resolved"),
        ignored: count_status(status_counts, "ignored"),
        archived: count_status(status_counts, "archived"),
        all: status_counts.values.sum
      },
      activity_events: events_by_type.except("error").values.sum,
      analytics: Logister::CliSerializer.analytics(read)
    }
  end

  private

  def event_type_counts(counts)
    IngestEvent.event_types.keys.index_with do |event_type|
      counts[event_type].to_i + counts[IngestEvent.event_types.fetch(event_type)].to_i
    end
  end

  def count_status(counts, status)
    counts[status].to_i + counts[status.to_sym].to_i + counts[ErrorGroup.statuses.fetch(status)].to_i
  end

  def postgres_rollup(events, project_id)
    counts = event_type_counts(events.group(:event_type).count)
    {
      event_type_counts: counts,
      active_project_ids: counts.values.sum.positive? ? [ project_id ] : [],
      activity_event_counts: { project_id => counts.except("error").values.sum },
      latest_event_at_by_project: { project_id => events.maximum(:occurred_at) }.compact
    }
  end
end

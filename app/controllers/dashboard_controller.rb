class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    accessible = current_user.accessible_projects
    project_ids = accessible.pluck(:id)

    @projects = accessible.order(created_at: :desc).limit(6)
    summary = dashboard_summary_for(project_ids)
    @projects_count = summary[:projects_count]
    @api_keys_count = summary[:api_keys_count]
    @events_last_24h = summary[:events_last_24h]
    @recent_events = IngestEvent.where(id: summary[:recent_event_ids]).includes(:project).order(occurred_at: :desc)
    @error_views = build_error_views(
      IngestEvent.where(id: summary[:error_event_ids]).includes(:project).order(occurred_at: :desc)
    )
  end

  private

  def dashboard_summary_for(project_ids)
    return { projects_count: 0, api_keys_count: 0, events_last_24h: 0, recent_event_ids: [], error_event_ids: [] } if project_ids.empty?

    cache_key = [ "dashboard_summary", current_user.id, dashboard_cache_version(project_ids) ]

    safe_cache_fetch(cache_key, expires_in: 30.seconds) do
      {
        projects_count: Project.where(id: project_ids).count,
        api_keys_count: ApiKey.where(project_id: project_ids).count,
        events_last_24h: IngestEvent.where(project_id: project_ids).where("occurred_at >= ?", 24.hours.ago).count,
        recent_event_ids: IngestEvent.where(project_id: project_ids).order(occurred_at: :desc).limit(20).pluck(:id),
        error_event_ids: IngestEvent.where(project_id: project_ids, event_type: :error)
                                    .where("occurred_at >= ?", 7.days.ago)
                                    .order(occurred_at: :desc)
                                    .limit(320)
                                    .pluck(:id)
      }
    end
  end

  def dashboard_cache_version(project_ids)
    latest_event = IngestEvent.where(project_id: project_ids).maximum(:updated_at)&.utc&.to_i || 0
    latest_key = ApiKey.where(project_id: project_ids).maximum(:updated_at)&.utc&.to_i || 0
    [ latest_event, latest_key ]
  end

  def build_error_views(events)
    grouped = events.group_by do |event|
      [ event.project_id, event.fingerprint.presence || event.message.to_s.lines.first.to_s.strip.presence || event.uuid ]
    end

    grouped.map do |(_, fingerprint), grouped_events|
      latest = grouped_events.max_by { |event| event.occurred_at || Time.zone.at(0) }
      project = latest.project
      trend_points = 7.times.map do |index|
        date = Date.current - (6 - index)
        grouped_events.count { |event| event.occurred_at&.to_date == date }
      end

      {
        fingerprint: fingerprint,
        project: project,
        latest_event: latest,
        title: latest.message.to_s.lines.first.to_s.strip.presence || "Untitled error",
        events_count: grouped_events.length,
        trend: trend_points,
        stage: latest.context.is_a?(Hash) ? (latest.context["environment"] || latest.context[:environment]) : "production"
      }
    end.sort_by { |view| view[:latest_event].occurred_at || Time.zone.at(0) }.reverse.first(6)
  end
end

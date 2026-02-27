class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    accessible = current_user.accessible_projects
    @projects = accessible.order(created_at: :desc).limit(6)
    @projects_count = accessible.count
    @api_keys_count = ApiKey.where(project_id: accessible.select(:id)).count
    @events_last_24h = IngestEvent.where(project_id: accessible.select(:id))
                                  .where("occurred_at >= ?", 24.hours.ago)
                                  .count
    @recent_events = IngestEvent.where(project_id: accessible.select(:id))
                                .includes(:project)
                                .order(occurred_at: :desc)
                                .limit(20)
    @error_views = build_error_views(
      IngestEvent.where(project_id: accessible.select(:id), event_type: :error)
                 .includes(:project)
                 .where("occurred_at >= ?", 7.days.ago)
                 .order(occurred_at: :desc)
                 .limit(320)
    )
  end

  private

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

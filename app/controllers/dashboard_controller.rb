class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @projects_count = current_user.projects.count
    @api_keys_count = current_user.api_keys.count
    @events_last_24h = IngestEvent.joins(:project)
                                .where(projects: { user_id: current_user.id })
                                .where("occurred_at >= ?", 24.hours.ago)
                                .count
    @recent_events = IngestEvent.joins(:project)
                                .where(projects: { user_id: current_user.id })
                                .includes(:project)
                                .order(occurred_at: :desc)
                                .limit(20)
  end
end

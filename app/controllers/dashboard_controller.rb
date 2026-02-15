class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    accessible = current_user.accessible_projects
    @projects_count = accessible.count
    @api_keys_count = ApiKey.where(project_id: accessible.select(:id)).count
    @events_last_24h = IngestEvent.where(project_id: accessible.select(:id))
                                  .where("occurred_at >= ?", 24.hours.ago)
                                  .count
    @recent_events = IngestEvent.where(project_id: accessible.select(:id))
                                .includes(:project)
                                .order(occurred_at: :desc)
                                .limit(20)
  end
end

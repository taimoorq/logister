class DashboardEventsController < ApplicationController
  include DashboardExplorerFiltering

  before_action :authenticate_user!

  def index
    @projects = current_user.active_projects.order(created_at: :desc).to_a
    @projects_by_id = @projects.index_by(&:id)
    project_ids = @projects_by_id.keys
    @filters = dashboard_explorer_filters(project_ids)
    @filter_labels = dashboard_explorer_filter_labels(@filters, @projects_by_id)
    @events = Dashboard.explorer_events_for(project_ids, **@filters).to_a
    @event_limit = Dashboard::EXPLORER_EVENT_LIMIT
  end
end

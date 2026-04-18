class ProjectActivityController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    @activity_events = @project.ingest_events
                               .where.not(event_type: :error)
                               .order(occurred_at: :desc)
                               .limit(200)

    render "projects/activity"
  end
end

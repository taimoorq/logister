class ProjectMonitorsController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    @check_in_monitors = @project.check_in_monitors.recent_first.limit(10)
    @missed_check_ins_count = @check_in_monitors.count { |monitor| monitor.status == "missed" }

    render "projects/monitors"
  end
end

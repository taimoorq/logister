class ProjectMonitorsController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project, only: :show
  before_action :set_managed_project, only: :update

  def show
    @check_in_monitors = @project.check_in_monitors.recent_first.limit(10)
    @missed_check_ins_count = @check_in_monitors.count { |monitor| monitor.status == "missed" }
    @can_manage_monitors = @project.managed_by?(current_user)

    render "projects/monitors"
  end

  def update
    monitor = @project.check_in_monitors.find(params[:id])

    case monitoring_state
    when "paused"
      monitor.pause_monitoring!
      notice = "Monitoring paused for #{monitor.slug}. Check-ins remain available, but alerts are off."
    when "active"
      monitor.resume_monitoring!
      notice = "Monitoring resumed for #{monitor.slug}."
    else
      return redirect_to monitors_project_path(@project), alert: "Choose a valid monitor state."
    end

    redirect_to monitors_project_path(@project), notice: notice
  end

  private

  def monitoring_state
    params.require(:check_in_monitor).permit(:monitoring_state)[:monitoring_state]
  end
end

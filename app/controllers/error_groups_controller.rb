class ErrorGroupsController < ApplicationController
  include ProjectInboxData

  before_action :authenticate_user!
  before_action :set_project
  before_action :set_group

  # PATCH /projects/:project_uuid/error_groups/:uuid/resolve
  def resolve
    @group.mark_resolved!
    respond_with_stream
  end

  # PATCH /projects/:project_uuid/error_groups/:uuid/ignore
  def ignore
    @group.ignore!
    respond_with_stream
  end

  # PATCH /projects/:project_uuid/error_groups/:uuid/archive
  def archive
    @group.archive!
    respond_with_stream
  end

  # PATCH /projects/:project_uuid/error_groups/:uuid/reopen
  def reopen
    @group.reopen!
    respond_with_stream
  end

  private

  def set_project
    @project = current_user.accessible_projects.find_by!(uuid: params[:project_uuid])
  end

  def set_group
    @group = @project.error_groups.find_by!(uuid: params[:uuid])
  end

  def respond_with_stream
    filter  = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    query   = params[:q].to_s.strip
    @groups = inbox_groups(@project, filter: filter, query: query)
    @counts = inbox_counts(@project)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          # Re-render the inbox list with the group removed/updated
          turbo_stream.replace("project_inbox",
            partial: "projects/inbox_table",
            locals: { project: @project, groups: @groups, selected_uuid: nil, filter: filter, query: query }
          ),
          # Update sidebar counts
          turbo_stream.replace("inbox_counts",
            partial: "projects/inbox_counts",
            locals: { project: @project, counts: @counts, filter: filter, query: query }
          ),
          # Clear the detail pane
          turbo_stream.replace("error_detail",
            partial: "projects/empty_detail"
          )
        ]
      end
      format.html { redirect_to project_path(@project, filter: filter, q: query) }
    end
  end
end

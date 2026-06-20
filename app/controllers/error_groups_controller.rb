class ErrorGroupsController < ApplicationController
  include ProjectInboxData

  before_action :authenticate_user!
  before_action :set_project
  before_action :set_group

  # GET /projects/:project_uuid/error_groups/:uuid/export
  def export
    include_occurrences = ActiveModel::Type::Boolean.new.cast(params[:include_occurrences]) || false
    preview = ActiveModel::Type::Boolean.new.cast(params[:preview]) || false
    payload = ErrorGroupJsonExporter.call(
      project: @project,
      group: @group,
      include_occurrences: include_occurrences,
      logister_url: inbox_project_url(@project, group_uuid: @group.uuid)
    )

    send_data(
      JSON.pretty_generate(payload),
      filename: "logister-error-#{@group.uuid}.json",
      type: "application/json; charset=utf-8",
      disposition: preview ? "inline" : "attachment"
    )
  end

  # PATCH /projects/:project_uuid/error_groups/:uuid/resolve
  def resolve
    @group.mark_resolved!
    notify_status_change("resolved")
    respond_with_stream
  end

  # PATCH /projects/:project_uuid/error_groups/:uuid/ignore
  def ignore
    @group.ignore!
    notify_status_change("ignored")
    respond_with_stream
  end

  # PATCH /projects/:project_uuid/error_groups/:uuid/archive
  def archive
    @group.archive!
    notify_status_change("archived")
    respond_with_stream
  end

  # PATCH /projects/:project_uuid/error_groups/:uuid/reopen
  def reopen
    @group.reopen!
    notify_status_change("unresolved")
    respond_with_stream
  end

  private

  def set_project
    @project = current_user.accessible_projects.find_by!(uuid: params[:project_uuid])
  end

  def set_group
    @group = @project.error_groups.find_by!(uuid: params[:uuid])
  end

  def notify_status_change(status)
    ProjectWorkflowNotificationJob.perform_later(
      @group.id,
      "status_change",
      {
        "status" => status,
        "actor_user_id" => current_user.id,
        "actor_name" => current_user.name.presence || current_user.email,
        "changed_at" => Time.current.utc.iso8601
      }
    )
  end

  def respond_with_stream
    filter  = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    query   = params[:q].to_s.strip
    assignee = normalize_inbox_assignee_filter(@project, params[:assignee], viewer: current_user)
    @groups = inbox_groups(@project, filter: filter, query: query, assignee: assignee, viewer: current_user)
    @counts = inbox_counts(@project, assignee: assignee, viewer: current_user)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          # Re-render the inbox list with the group removed/updated
          turbo_stream.replace("project_inbox",
            partial: "projects/inbox_table",
            locals: {
              project: @project,
              groups: @groups,
              latest_events: inbox_latest_events(@groups),
              group_trends: inbox_group_trends(@project, @groups),
              has_activity_events: @groups.empty? && project_has_activity_events?(@project),
              selected_uuid: nil,
              filter: filter,
              query: query,
              assignee: assignee
            }
          ),
          # Update sidebar counts
          turbo_stream.replace("inbox_counts",
            partial: "projects/inbox_counts",
            locals: { project: @project, counts: @counts, filter: filter, query: query, assignee: assignee }
          ),
          # Clear the detail pane
          turbo_stream.replace("error_detail",
            partial: "projects/empty_detail"
          )
        ]
      end
      format.html { redirect_to inbox_project_path(@project, filter: filter, q: query, assignee: assignee) }
    end
  end
end

class ErrorGroupAssignmentsController < ApplicationController
  include ProjectEventDetailData
  include ProjectInboxData

  before_action :authenticate_user!
  before_action :set_project
  before_action :set_group

  def update
    assignee_uuid = params[:assigned_user_id].to_s.strip

    if assignee_uuid.present?
      @group.assign_to!(@project.assignable_users.find_by!(uuid: assignee_uuid), assigned_by: current_user)
    else
      @group.clear_assignment!
    end

    respond_with_assignment
  end

  def destroy
    @group.clear_assignment!
    respond_with_assignment
  end

  private

  def set_project
    @project = current_user.accessible_projects.find_by!(uuid: params[:project_uuid] || params[:project_id])
  end

  def set_group
    group_uuid = params[:error_group_uuid] || params[:uuid]
    @group = @project.error_groups.find_by!(uuid: group_uuid)
  end

  def respond_with_assignment
    filter = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    query = params[:q].to_s.strip
    assignee = normalize_inbox_assignee_filter(@project, params[:assignee], viewer: current_user)
    profile_filters = normalize_inbox_profile_filters(@project)
    sort = normalize_inbox_sort(@project, params[:sort])
    page = inbox_page(@project, filter: filter, query: query, assignee: assignee, viewer: current_user, dimensions: profile_filters, sort: sort)
    groups = page.groups
    counts = inbox_counts(@project, assignee: assignee, viewer: current_user)
    selected_uuid = groups.any? { |group| group.id == @group.id } ? @group.uuid : nil

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            "project_inbox",
            partial: "projects/inbox_table",
            locals: {
              project: @project,
              groups: groups,
              latest_events: inbox_latest_events(groups),
              group_trends: inbox_group_trends(@project, groups),
              impact_summaries: inbox_impact_summaries(@project, groups),
              has_activity_events: groups.empty? && project_has_activity_events?(@project),
              selected_uuid: selected_uuid,
              filter: filter,
              query: query,
              assignee: assignee,
              sort: sort,
              profile_filters: profile_filters,
              next_cursor: page.next_cursor
            },
            method: :morph
          ),
          turbo_stream.replace(
            "inbox_counts",
            partial: "projects/inbox_counts",
            locals: { project: @project, counts: counts, filter: filter, query: query, assignee: assignee },
            method: :morph
          ),
          detail_stream(selected_uuid, filter: filter, query: query, assignee: assignee)
        ]
      end

      redirect_params = inbox_profile_state_params(@project).merge(filter: filter, q: query, assignee: assignee)
      redirect_params[:group_uuid] = selected_uuid if selected_uuid.present?
      format.html { redirect_to inbox_project_path(@project, redirect_params), notice: "Assignment updated." }
    end
  end

  def detail_stream(selected_uuid, filter:, query:, assignee:)
    latest_event = @group.latest_event_record
    if selected_uuid.present? && latest_event.present?
      detail_data = build_project_event_detail(@project, latest_event, group: @group)
      return turbo_stream.replace(
        "error_detail",
        partial: "project_events/event_detail",
        locals: {
          project: @project,
          event: detail_data[:event],
          group: detail_data[:group],
          occurrences: detail_data[:occurrences],
          related_logs: detail_data[:related_logs],
          impact_summary: detail_data[:impact_summary],
          filter: filter,
          query: query,
          assignee: assignee,
          assignable_users: @project.assignable_users.to_a,
          tab: params[:tab],
          frame_scope: params[:frame_scope],
          frame: params[:frame]
        },
        method: :morph
      )
    end

    turbo_stream.replace("error_detail", partial: "projects/empty_detail", method: :morph)
  end
end

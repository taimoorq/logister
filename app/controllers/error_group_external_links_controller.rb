# frozen_string_literal: true

class ErrorGroupExternalLinksController < ApplicationController
  include ProjectEventDetailData
  include ProjectInboxData

  before_action :authenticate_user!
  before_action :set_project
  before_action :set_group
  before_action :set_external_link, only: :destroy

  def create
    @external_link = @group.external_links.new(external_link_params)
    @external_link.project = @project
    @external_link.created_by = current_user

    if @external_link.save
      respond_with_detail(notice: "GitHub link attached.")
    else
      respond_with_detail(status: :unprocessable_content, alert: @external_link.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @external_link.destroy
    respond_with_detail(notice: "GitHub link removed.")
  end

  private

  def set_project
    @project = current_user.accessible_projects.find_by!(uuid: params[:project_uuid] || params[:project_id])
  end

  def set_group
    group_uuid = params[:error_group_uuid] || params[:uuid]
    @group = @project.error_groups.find_by!(uuid: group_uuid)
  end

  def set_external_link
    @external_link = @group.external_links.find_by!(uuid: params[:uuid])
  end

  def external_link_params
    params.require(:error_group_external_link).permit(:url)
  end

  def respond_with_detail(status: :ok, notice: nil, alert: nil)
    filter = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    query = params[:q].to_s.strip
    assignee = normalize_inbox_assignee_filter(@project, params[:assignee], viewer: current_user)

    respond_to do |format|
      format.turbo_stream do
        response.status = status
        render turbo_stream: detail_stream(filter: filter, query: query, assignee: assignee)
      end

      redirect_params = { filter: filter, q: query, assignee: assignee, group_uuid: @group.uuid }
      format.html do
        redirect_to inbox_project_path(@project, redirect_params),
                    notice: notice,
                    alert: alert
      end
    end
  end

  def detail_stream(filter:, query:, assignee:)
    latest_event = @group.latest_event_record
    return turbo_stream.replace("error_detail", partial: "projects/empty_detail") if latest_event.blank?

    detail_data = build_project_event_detail(@project, latest_event, group: @group)
    turbo_stream.replace(
      "error_detail",
      partial: "project_events/event_detail",
      locals: {
        project: @project,
        event: detail_data[:event],
        group: detail_data[:group],
        occurrences: detail_data[:occurrences],
        related_logs: detail_data[:related_logs],
        filter: filter,
        query: query,
        assignee: assignee,
        assignable_users: @project.assignable_users.to_a,
        tab: params[:tab],
        frame_scope: params[:frame_scope],
        frame: params[:frame],
        external_link_errors: @external_link&.errors&.full_messages || []
      }
    )
  end
end

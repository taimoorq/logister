# frozen_string_literal: true

module Github
  class IssuesController < ApplicationController
    include ProjectEventDetailData
    include ProjectInboxData

    before_action :authenticate_user!
    before_action :set_project
    before_action :set_group

    def create
      result = Github::IssueCreator.call(
        project: @project,
        group: @group,
        event: latest_event,
        source_excerpt: source_excerpt_param,
        repository: selected_repository,
        logister_url: inbox_project_url(@project, group_uuid: @group.uuid)
      )
      attach_issue_link(result)

      respond_with_detail(notice: "GitHub issue created.")
    rescue Github::IssueCreator::PermissionError => error
      respond_with_detail(status: :unprocessable_content, alert: error.message)
    rescue Github::IssueCreator::Error => error
      Rails.logger.info("github issue creation failed: #{error.class} #{error.message}")
      respond_with_detail(status: :unprocessable_content, alert: error.message)
    end

    private

    def set_project
      @project = current_user.accessible_projects.find_by!(uuid: params[:project_uuid] || params[:project_id])
    end

    def set_group
      @group = @project.error_groups.find_by!(uuid: params[:error_group_uuid] || params[:uuid])
    end

    def selected_repository
      return @selected_repository if defined?(@selected_repository)

      @selected_repository = if params[:repository_uuid].present?
        @project.source_repositories.github.enabled.find_by!(uuid: params[:repository_uuid])
      else
        @project.source_repositories.github.enabled.includes(:github_installation, github_repository: :github_installation).find(&:github_issue_creation_available?)
      end
    end

    def latest_event
      @latest_event ||= @group.latest_event_record
    end

    def source_excerpt_param
      url = params[:source_url].to_s.strip.presence
      url ? { source_url: url } : nil
    end

    def attach_issue_link(result)
      link = @group.external_links.find_or_initialize_by(url: result.html_url)
      link.assign_attributes(
        project: @project,
        created_by: current_user,
        title: result.title,
        metadata: (link.metadata || {}).merge(
          "source" => "github_api",
          "body" => result.body
        ).compact
      )
      link.save!
    end

    def respond_with_detail(status: :ok, notice: nil, alert: nil)
      @external_link_errors = Array(alert).compact
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
          external_link_errors: @external_link_errors
        }
      )
    end
  end
end

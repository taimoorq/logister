# frozen_string_literal: true

module ProjectEventResponses
  private

  def render_inbox_response
    if turbo_frame_request? && request.headers["Turbo-Frame"] == "project_inbox"
      render partial: "projects/inbox_table", locals: {
        project:       @project,
        groups:        @groups,
        latest_events: @latest_events,
        android_mapping_resolutions: @android_mapping_resolutions,
        ios_symbol_coverages: @ios_symbol_coverages,
        group_trends:  @group_trends,
        impact_summaries: @impact_summaries,
        evidence_signals: @evidence_signals,
        has_activity_events: @has_activity_events,
        selected_uuid: @selected_uuid,
        filter:        @filter,
        query:         @query,
        assignee:      @assignee_filter,
        sort:          @sort,
        profile_filters: @profile_filters,
        next_cursor:   @next_cursor
      }
    elsif turbo_frame_request?
      head :unprocessable_content
    else
      redirect_to inbox_project_path(@project, inbox_profile_redirect_params.merge(filter: @filter, q: @query, assignee: @assignee_filter, group_uuid: @selected_uuid))
    end
  end

  def render_event_response
    if turbo_frame_request? && request.headers["Turbo-Frame"] == "stack_frame_source" && @project.integration_ruby?
      render partial: "project_events/ruby_stack_frame_source", locals: {
        project:     @project,
        event:       @event,
        group:       @group,
        filter_param: @filter,
        query_param: @query,
        assignee_param: @assignee_filter,
        frame_scope: @frame_scope,
        selected_frame_index: @frame
      }
    elsif turbo_frame_request? && request.headers["Turbo-Frame"] == "error_detail"
      render partial: "project_events/event_detail", locals: {
        project:     @project,
        event:       @event,
        group:       @group,
        occurrences: @occurrences,
        related_logs: @related_logs,
        impact_summary: @impact_summary,
        variant_summary: @variant_summary,
        filter:      @filter,
        query:       @query,
        assignee:    @assignee_filter,
        assignable_users: @assignable_users,
        tab:         @tab,
        frame_scope: @frame_scope,
        frame:       @frame
      }
    elsif turbo_frame_request?
      head :unprocessable_content
    else
      # Fallback: if this came from the project inbox workflow, keep users in that workbench.
      if params[:group_uuid].present? || params[:filter].present? || params[:q].present?
        redirect_to inbox_project_path(
          @project,
          inbox_profile_redirect_params.merge(
            filter: @filter,
            q: @query,
            assignee: @assignee_filter,
            group_uuid: @group&.uuid || params[:group_uuid],
            event_uuid: @event.uuid,
            tab: @tab
          )
        )
      else
        # Full page load — standalone event page.
        render :show
      end
    end
  end
end

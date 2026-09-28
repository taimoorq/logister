# frozen_string_literal: true

class ProjectRequestsController < ApplicationController
  include ProjectScope
  before_action :authenticate_user!
  before_action :set_accessible_project

  Anchor = Data.define(:uuid, :context, :occurred_at, :created_at)

  def show
    raise ActiveRecord::RecordNotFound unless ProjectCorrelationPolicy.enabled?(@project)

    span = @project.trace_spans.find_by(uuid: params[:uuid])
    at = span&.started_at || Time.iso8601(params[:occurred_at].to_s)
    environment = span&.context_value("environment").presence || params[:environment].presence || "production"
    read = ProjectCorrelationRecords.new(from: at - 1.second, to: at + 1.second, uuid: params[:uuid])
      .call(project: @project, environments: [ environment ], signals: [ "span" ])
    row = read[:rows].find { |candidate| candidate["uuid"] == params[:uuid] }
    raise ActiveRecord::RecordNotFound unless row

    @event = Anchor.new(uuid: row["uuid"], context: row.slice("trace_id", "span_id", "parent_span_id", "request_id", "environment", "release"), occurred_at: at, created_at: at)
    @correlation_path = project_request_path(@project, @event.uuid, occurred_at: at.iso8601(6), environment:)
    @result = ProjectCorrelationsQuery.call(principal: current_user, project: @project, event: @event, from: params[:from], to: params[:to])
    @result[:partial] ||= read[:partial]
    render "project_correlations/show"
  rescue ArgumentError, ProjectCorrelationsQuery::InvalidRange, ProjectCorrelationPolicy::TooManyProjects => error
    @error = "Use an ISO 8601 occurrence timestamp and a window of up to 24 hours."
    @error = error.message unless error.is_a?(ArgumentError)
    render "project_correlations/show", status: :unprocessable_content
  rescue ActiveRecord::QueryCanceled
    @error = "This request lookup took too long. Try again with a shorter time range."
    render "project_correlations/show", status: :service_unavailable
  end
end

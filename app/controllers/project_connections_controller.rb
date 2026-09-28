# frozen_string_literal: true

class ProjectConnectionsController < ApplicationController
  include ProjectScope
  before_action :authenticate_user!
  before_action :set_accessible_project

  def index
    @filters = params.permit(:from, :to, :environment, :connected_project, :release, :app_version, :build_number, :group_uuid, :only_errors, :peer_release, :peer_app_version, :peer_build_number, :deployment_uuid).to_h
    @report = ProjectConnectionReport.new(principal: current_user, project: @project, params: @filters).call
    @filters["environment"] = @report[:environment]
    respond_to do |format|
      format.html do
        if params[:summary] == "1"
          render partial: "project_connections/summary", locals: { project: @project, report: @report, filters: @filters, error: nil }
        end
      end
      format.json do
        send_data @report.to_json, type: "application/json", filename: "logister-connected-evidence-#{@project.uuid}.json", disposition: "attachment"
      end
    end
  rescue ProjectConnectionReport::InvalidScope, ProjectCorrelationPolicy::TooManyProjects => error
    report_error(error.message, :unprocessable_content)
  rescue ActiveRecord::QueryCanceled
    report_error("This lookup took too long. Narrow the time window and try again.", :service_unavailable)
  end

  private

  def report_error(message, status)
    @error = message
    respond_to do |format|
      format.html do
        if params[:summary] == "1"
          render partial: "project_connections/summary", locals: { project: @project, report: nil, filters: @filters, error: message }, status:
        else
          render :index, status:
        end
      end
      format.json { render json: { error: message }, status: }
    end
  end
end

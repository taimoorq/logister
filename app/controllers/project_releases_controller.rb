# frozen_string_literal: true

class ProjectReleasesController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project
  before_action :require_mobile_project!

  def index
    @release_page = [ params[:page].to_i, 1 ].max
    @release_index = ProjectMobileReleaseIndex.new(
      @project,
      offset: (@release_page - 1) * ProjectMobileReleaseIndex::DEFAULT_LIMIT
    ).call
    @capability_snapshot = ProjectCapabilitySnapshot.for(@project)
    @distribution_snapshot = ProjectMobileDistributionSnapshot.new(@project).call

    render "projects/releases"
  end

  private

  def require_mobile_project!
    return if @project.integration_android? || @project.integration_ios?

    raise ActiveRecord::RecordNotFound
  end
end

# frozen_string_literal: true

class ProjectArchivesController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    @archive_investigation_search = ProjectArchiveInvestigationSearch.new(
      project: @project,
      params: params.fetch(:archive_search, {})
    )

    render "projects/archives"
  end
end

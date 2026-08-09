# frozen_string_literal: true

class ProjectPurgesController < ApplicationController
  before_action :authenticate_user!

  def retry
    purge = ProjectPurge.find(params[:id])
    Logister::ProjectPurgeResume.new(project_purge: purge, actor: current_user).call
    redirect_to projects_path(filter: "archived"), notice: "Permanent deletion purge ##{purge.id} was queued to resume."
  rescue Logister::ProjectPurgeResume::NotAuthorized, ActiveRecord::RecordNotFound
    head :not_found
  end
end

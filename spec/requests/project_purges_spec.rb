# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project purge retries", type: :request do
  include ActiveJob::TestHelper

  before { clear_enqueued_jobs }

  it "allows the requesting project owner to resume an awaiting external purge" do
    project = create(:project)
    purge = Logister::ProjectPurgeRequest.new(project: project, requested_by: project.user, enqueue: false).call
    purge.update!(status: "awaiting_external", current_step: "clickhouse")
    purge.steps.find_by!(store_name: "clickhouse").update!(status: "awaiting_external")
    sign_in project.user

    post retry_project_purge_path(purge)

    expect(response).to redirect_to(projects_path(filter: "archived"))
    expect(ProjectPurgeJob).to have_been_enqueued.with(purge.id)
    expect(purge.reload.status).to eq("tombstoned")
  end

  it "does not reveal a purge to an unrelated user" do
    project = create(:project)
    purge = Logister::ProjectPurgeRequest.new(project: project, requested_by: project.user, enqueue: false).call
    sign_in create(:user)

    post retry_project_purge_path(purge)

    expect(response).to have_http_status(:not_found)
    expect(ProjectPurgeJob).not_to have_been_enqueued
  end
end

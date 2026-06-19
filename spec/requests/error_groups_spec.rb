# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Error groups", type: :request do
  let(:project) { projects(:one) }
  let(:api_key) { api_keys(:one) }

  def create_error_group_for_project
    event = IngestEvent.create!(
      project: project,
      api_key: api_key,
      event_type: :error,
      level: "error",
      message: "Spec error",
      fingerprint: "spec-fp-#{SecureRandom.hex(4)}",
      occurred_at: Time.current
    )
    ErrorGroupingService.call(event)
    event.reload.error_group
  end

  describe "GET /projects/:project_uuid/error_groups/:uuid/export" do
    before { sign_in users(:one) }

    it "downloads an AI-friendly JSON export with summarized occurrences by default" do
      group = create_error_group_for_project

      get export_project_error_group_path(project, group)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.headers["Content-Disposition"]).to include("attachment", "logister-error-#{group.uuid}.json")

      payload = JSON.parse(response.body)
      expect(payload.dig("export", "format")).to eq("logister_error_group")
      expect(payload.dig("export", "include_all_occurrences")).to be(false)
      expect(payload.dig("error_group", "uuid")).to eq(group.uuid)
      expect(payload.dig("occurrences", "mode")).to eq("summary")
      expect(payload.fetch("occurrences")).not_to have_key("records")
    end

    it "can render the export inline for preview links" do
      group = create_error_group_for_project

      get export_project_error_group_path(project, group, preview: "1")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.headers["Content-Disposition"]).to include("inline", "logister-error-#{group.uuid}.json")
    end

    it "includes recent occurrence records when requested" do
      group = create_error_group_for_project
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        level: "error",
        message: "Spec error again",
        fingerprint: group.fingerprint,
        occurred_at: Time.current
      )
      ErrorGroupingService.call(event)

      get export_project_error_group_path(project, group, include_occurrences: "1")

      payload = JSON.parse(response.body)
      expect(payload.dig("export", "include_all_occurrences")).to be(false)
      expect(payload.dig("export", "include_occurrence_records")).to be(true)
      expect(payload.dig("export", "occurrence_record_limit")).to eq(50)
      expect(payload.dig("occurrences", "mode")).to eq("latest_records")
      expect(payload.dig("occurrences", "records").size).to eq(2)
      expect(payload.dig("occurrences", "record_limit")).to eq(50)
      expect(payload.dig("occurrences", "truncated")).to be(false)
      expect(payload.dig("occurrences", "records").map { |record| record.dig("ingest_event", "message") }).to include(
        "Spec error",
        "Spec error again"
      )
    end
  end

  describe "PATCH /projects/:project_uuid/error_groups/:uuid/resolve" do
    before { sign_in users(:one) }

    it "marks group resolved and returns turbo stream" do
      group = create_error_group_for_project
      expect(group).to be_unresolved

      patch resolve_project_error_group_path(project, group),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(group.reload).to be_resolved
    end

    it "redirects when HTML requested" do
      group = create_error_group_for_project

      patch resolve_project_error_group_path(project, group)

      expect(response).to redirect_to(inbox_project_path(project, filter: "unresolved", q: "", assignee: "all"))
    end

    it "returns 404 for group in another project" do
      # Create a group in project two, then request resolve using project one's path
      other_project = projects(:two)
      other_api_key = api_keys(:two)
      event = IngestEvent.create!(
        project: other_project,
        api_key: other_api_key,
        event_type: :error,
        message: "Other project error",
        fingerprint: "other-#{SecureRandom.hex(4)}",
        occurred_at: Time.current
      )
      ErrorGroupingService.call(event)
      group = event.reload.error_group

      patch resolve_project_error_group_path(project, group)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /projects/:project_uuid/error_groups/:uuid/ignore" do
    before { sign_in users(:one) }

    it "marks group ignored" do
      group = create_error_group_for_project

      patch ignore_project_error_group_path(project, group),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(group.reload).to be_ignored
    end
  end

  describe "PATCH /projects/:project_uuid/error_groups/:uuid/archive" do
    before { sign_in users(:one) }

    it "marks group archived" do
      group = create_error_group_for_project

      patch archive_project_error_group_path(project, group),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(group.reload).to be_archived
    end
  end

  describe "PATCH /projects/:project_uuid/error_groups/:uuid/reopen" do
    before { sign_in users(:one) }

    it "reopens resolved group" do
      group = create_error_group_for_project
      group.mark_resolved!

      patch reopen_project_error_group_path(project, group),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(group.reload).to be_unresolved
    end
  end

  describe "PATCH /projects/:project_uuid/error_groups/:error_group_uuid/assignment" do
    before { sign_in users(:one) }

    it "assigns the group to a project member and returns turbo stream" do
      group = create_error_group_for_project
      member = create(:user)
      create(:project_membership, project: project, user: member)

      patch project_error_group_assignment_path(project, group),
            params: { assigned_user_id: member.uuid },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(group.reload.assignee).to eq(member)
      expect(group.assigned_by).to eq(users(:one))
      expect(response.body).to include("project_inbox", "inbox_counts", "error_detail")
    end

    it "lets a shared member assign a visible group to themselves" do
      group = create_error_group_for_project
      sign_in users(:two)

      patch project_error_group_assignment_path(project, group),
            params: { assigned_user_id: users(:two).uuid }

      expect(response).to redirect_to(inbox_project_path(project, filter: "unresolved", q: "", assignee: "all", group_uuid: group.uuid))
      expect(group.reload.assignee).to eq(users(:two))
      expect(group.assigned_by).to eq(users(:two))
    end

    it "returns 404 for a user without project access" do
      group = create_error_group_for_project
      outsider = create(:user)

      patch project_error_group_assignment_path(project, group),
            params: { assigned_user_id: outsider.uuid }

      expect(response).to have_http_status(:not_found)
      expect(group.reload.assignee).to be_nil
    end
  end

  describe "DELETE /projects/:project_uuid/error_groups/:error_group_uuid/assignment" do
    before { sign_in users(:one) }

    it "clears the assignment" do
      group = create_error_group_for_project
      group.assign_to!(users(:one), assigned_by: users(:one))

      delete project_error_group_assignment_path(project, group),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(group.reload.assignee).to be_nil
      expect(group.assigned_by).to be_nil
      expect(group.assigned_at).to be_nil
    end
  end

  describe "authentication" do
    it "requires authentication" do
      group = create_error_group_for_project
      patch resolve_project_error_group_path(project, group)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end

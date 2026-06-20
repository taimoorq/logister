# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project retention policies", type: :request do
  describe "GET /projects/:uuid/settings?section=data" do
    it "shows archive object keys, sizes, and failure details for project managers" do
      project = projects(:one)
      archive_key = "telemetry/ingest_events/project=#{project.uuid}/year=2026/month=06/day=20/archive.jsonl.gz"
      create(
        :telemetry_archive,
        project: project,
        scope: "hot_events",
        rows: 7,
        bytes: 2.kilobytes,
        objects: [
          {
            "key" => archive_key,
            "rows" => 7,
            "bytes" => 2.kilobytes
          }
        ],
        created_at: 2.minutes.ago
      )
      create(
        :telemetry_archive,
        project: project,
        record_type: "trace_spans",
        scope: "trace_spans",
        status: "failed",
        rows: 0,
        bytes: 0,
        objects: [],
        error_message: "Logister::TelemetryArchiveExporter::Error: storage unavailable",
        created_at: 1.minute.ago
      )
      sign_in users(:one)

      get settings_project_path(project, section: "data")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Recent archive runs")
      expect(response.body).to include("Activity events")
      expect(response.body).to include("Trace spans")
      expect(response.body).to include("1 object")
      expect(response.body).to include("2 KB")
      expect(response.body).to include(archive_key)
      expect(response.body).to include("Failed")
      expect(response.body).to include("storage unavailable")
    end
  end

  describe "PATCH /projects/:uuid/retention_policy" do
    it "updates an owned project's retention policy" do
      project = projects(:one)
      sign_in users(:one)

      patch project_retention_policy_path(project), params: {
        project_retention_policy: {
          hot_retention_days: "60",
          trace_retention_days: "90",
          error_retention_days: "",
          archive_enabled: "1",
          archive_before_delete: "0"
        }
      }

      expect(response).to redirect_to(settings_project_path(project, section: "data"))
      policy = ProjectRetentionPolicy.find_by!(project: project)
      expect(policy.hot_retention_days).to eq(60)
      expect(policy.trace_retention_days).to eq(90)
      expect(policy.error_retention_days).to be_nil
      expect(policy.archive_enabled).to be true
      expect(policy.archive_before_delete).to be false
    end

    it "renders settings with validation errors" do
      project = projects(:one)
      sign_in users(:one)

      patch project_retention_policy_path(project), params: {
        project_retention_policy: {
          hot_retention_days: "30",
          trace_retention_days: "30",
          archive_enabled: "0",
          archive_before_delete: "1"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Data retention")
      expect(response.body).to include("requires retention exports to be enabled")
    end

    it "allows project admins to update retention settings" do
      project_memberships(:one).update!(role: :admin)
      sign_in users(:two)

      patch project_retention_policy_path(projects(:one)), params: {
        project_retention_policy: {
          hot_retention_days: "7",
          trace_retention_days: "7"
        }
      }

      expect(response).to redirect_to(settings_project_path(projects(:one), section: "data"))
    end

    it "does not allow viewers to update retention settings" do
      sign_in users(:two)

      patch project_retention_policy_path(projects(:one)), params: {
        project_retention_policy: {
          hot_retention_days: "7",
          trace_retention_days: "7"
        }
      }

      expect(response).to have_http_status(:not_found)
    end
  end
end

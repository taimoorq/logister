# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project retention policies", type: :request do
  describe "GET /projects/:uuid/settings?section=data" do
    def setup_archive_center_state(project)
      retention_policy = ProjectRetentionPolicy.for(project: project)
      retention_policy.update!(
        archive_enabled: true,
        archive_before_delete: true,
        last_retention_run_at: Time.current,
        last_archive_run_at: 2.minutes.ago,
        last_retention_result: {
          candidates: {
            hot_events: 7,
            trace_spans: 4,
            closed_error_groups: 0
          },
          deleted: {
            hot_events: 7,
            trace_spans: 0,
            closed_error_groups: 0
          }
        }
      )
      archive_key = "telemetry/ingest_events/project=#{project.uuid}/year=2026/month=06/day=20/archive.jsonl.gz"
      create(
        :telemetry_archive,
        project: project,
        scope: "hot_events",
        before_at: retention_policy.last_retention_run_at - retention_policy.hot_retention_days.days,
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
        before_at: retention_policy.last_retention_run_at - retention_policy.trace_retention_days.days,
        rows: 0,
        bytes: 0,
        objects: [],
        error_message: "Logister::TelemetryArchiveExporter::Error: storage unavailable",
        created_at: 1.minute.ago
      )

      archive_key
    end

    it "shows a path-based archive center overview for project managers" do
      project = projects(:one)
      setup_archive_center_state(project)
      sign_in users(:one)

      get settings_project_path(project, section: "data")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Archive Center")
      expect(response.body).to include("Archived data")
      expect(response.body).to include("Needs attention")
      expect(response.body).to include("Choose a path")
      expect(response.body).to include("Review coverage")
      expect(response.body).to include("View catalog")
      expect(response.body).to include("Search archives")
      expect(response.body).to include("archive_path=search_archives")
      expect(response.body).to include("Archive retained data")
      expect(response.body).to include("Require archive before deletion")
    end

    it "collapses saved retention settings into a compact summary row" do
      project = projects(:one)
      policy = ProjectRetentionPolicy.for(project: project)
      policy.update!(
        hot_retention_days: 60,
        trace_retention_days: 90,
        error_retention_days: nil,
        archive_enabled: true,
        archive_before_delete: true
      )
      sign_in users(:one)

      get settings_project_path(project, section: "data")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML.parse(response.body)
      details = document.at_css("details#retention-policy-settings")
      summary_text = details.at_css("summary").text.squish

      expect(details).to be_present
      expect(details["open"]).to be_nil
      expect(summary_text).to include("Events: 60 days")
      expect(summary_text).to include("Traces: 90 days")
      expect(summary_text).to include("Closed errors: Forever")
      expect(summary_text).to include("Archive: Protected before deletion")
      expect(details.at_css("select[name='project_retention_policy[hot_retention_days]']")).to be_present
      expect(details.at_css("input[name='project_retention_policy[archive_before_delete]'][type='checkbox']")).to be_present
    end

    it "shows coverage details on the coverage path" do
      project = projects(:one)
      setup_archive_center_state(project)
      sign_in users(:one)

      get settings_project_path(project, section: "data", archive_path: "coverage")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Coverage by data type")
      expect(response.body).to include("Activity events")
      expect(response.body).to include("Trace spans")
      expect(response.body).to include("Closed error groups")
      expect(response.body).to include("Runs")
    end

    it "shows object keys, sizes, and failure details on the catalog path" do
      project = projects(:one)
      archive_key = setup_archive_center_state(project)
      sign_in users(:one)

      get settings_project_path(project, section: "data", archive_path: "catalog")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Archive catalog")
      expect(response.body).to include("1 object")
      expect(response.body).to include("2 KB")
      expect(response.body).to include(archive_key)
      expect(response.body).to include("Failed")
      expect(response.body).to include("storage unavailable")
    end

    it "searches hot telemetry and candidate archive runs on the Search Archives path" do
      project = projects(:one)
      setup_archive_center_state(project)
      event = create(
        :ingest_event,
        :log,
        project: project,
        api_key: api_keys(:one),
        message: "Checkout rollback marker",
        context: { "request_id" => "req-archive-1", "environment" => "production" }
      )
      create(
        :trace_span,
        project: project,
        api_key: api_keys(:one),
        trace_id: "trace-archive-1",
        name: "GET /checkout",
        context: { "request_id" => "req-archive-1", "environment" => "production" }
      )
      sign_in users(:one)

      get settings_project_path(
        project,
        section: "data",
        archive_path: "search_archives",
        archive_search: {
          q: "Checkout",
          request_id: "req-archive-1"
        }
      )

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Search Archives")
      expect(response.body).to include("Hot event matches")
      expect(response.body).to include("Hot span matches")
      expect(response.body).to include("Candidate archive runs")
      expect(response.body).to include(event.message)
      expect(response.body).to include("GET /checkout")
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
      expect(response.body).to include("requires Archive retained data to be enabled")
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

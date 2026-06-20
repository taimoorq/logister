# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project notification preferences", type: :request do
  describe "PATCH /projects/:uuid/notification_preference" do
    it "updates the current user's project email settings" do
      sign_in users(:one)

      patch project_notification_preference_path(projects(:one)), params: {
        project_notification_preference: {
          first_occurrence_enabled: "0",
          regression_enabled: "1",
          frequent_error_enabled: "1",
          frequent_error_threshold_count: "50",
          frequent_error_window_minutes: "30",
          milestone_alerts_enabled: "1",
          workflow_mode: "all_project",
          monitor_alerts_enabled: "0",
          project_spike_enabled: "1",
          project_spike_threshold_count: "250",
          project_spike_window_minutes: "15",
          performance_alerts_enabled: "1",
          performance_p95_threshold_ms: "1500",
          release_notifications_enabled: "1",
          usage_notifications_enabled: "0",
          retention_notifications_enabled: "1",
          environment_filter: "production",
          severity_filter: "error",
          status_filter: "all",
          immediate_email_limit_per_hour: "5",
          quiet_hours_enabled: "1",
          quiet_hours_start: "21",
          quiet_hours_end: "6",
          digest_frequency: "weekly",
          digest_send_hour: "14",
          time_zone: "Eastern Time (US & Canada)"
        }
      }

      expect(response).to redirect_to(settings_project_path(projects(:one), section: "notifications"))
      preference = ProjectNotificationPreference.find_by!(project: projects(:one), user: users(:one))
      expect(preference.first_occurrence_enabled).to be false
      expect(preference.regression_enabled).to be true
      expect(preference.frequent_error_enabled).to be true
      expect(preference.frequent_error_threshold_count).to eq(50)
      expect(preference.frequent_error_window_minutes).to eq(30)
      expect(preference.milestone_alerts_enabled).to be true
      expect(preference.workflow_mode).to eq("all_project")
      expect(preference.monitor_alerts_enabled).to be false
      expect(preference.project_spike_enabled).to be true
      expect(preference.project_spike_threshold_count).to eq(250)
      expect(preference.performance_alerts_enabled).to be true
      expect(preference.performance_p95_threshold_ms).to eq(1500)
      expect(preference.release_notifications_enabled).to be true
      expect(preference.usage_notifications_enabled).to be false
      expect(preference.retention_notifications_enabled).to be true
      expect(preference.environment_filter).to eq("production")
      expect(preference.severity_filter).to eq("error")
      expect(preference.status_filter).to eq("all")
      expect(preference.immediate_email_limit_per_hour).to eq(5)
      expect(preference.quiet_hours_enabled).to be true
      expect(preference.quiet_hours_start).to eq(21)
      expect(preference.quiet_hours_end).to eq(6)
      expect(preference.digest_frequency).to eq("weekly")
      expect(preference.digest_send_hour).to eq(14)
      expect(preference.time_zone).to eq("Eastern Time (US & Canada)")
    end

    it "returns to the current notification path after saving" do
      sign_in users(:one)

      patch project_notification_preference_path(projects(:one), notification_path: "health"), params: {
        notification_path: "health",
        project_notification_preference: {
          project_spike_enabled: "1",
          project_spike_threshold_count: "125",
          project_spike_window_minutes: "10"
        }
      }

      expect(response).to redirect_to(settings_project_path(projects(:one), section: "notifications", notification_path: "health"))
      preference = ProjectNotificationPreference.find_by!(project: projects(:one), user: users(:one))
      expect(preference.project_spike_enabled).to be true
      expect(preference.project_spike_threshold_count).to eq(125)
      expect(preference.project_spike_window_minutes).to eq(10)
    end

    it "renders notification purpose paths before individual controls" do
      sign_in users(:one)

      get settings_project_path(projects(:one), section: "notifications")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Start with the reason you want email")
      expect(response.body).to include("Error triage alerts")
      expect(response.body).to include("Project health alerts")
      expect(response.body).to include("Team workflow routing")
      expect(response.body).to include("Digest summaries")
      expect(response.body).to include("Delivery limits")
      expect(response.body).to include("Operational notices")
      expect(response.body).not_to include("New error groups")
      expect(response.body).not_to include("Project-wide error spike")
      expect(response.body).not_to include("Hourly immediate email limit")
    end

    it "renders focused notification controls for the selected purpose" do
      sign_in users(:one)

      get settings_project_path(projects(:one), section: "notifications", notification_path: "errors")

      expect(response.body).to include("New error groups")
      expect(response.body).to include("Reopened error groups")
      expect(response.body).to include("Lifetime count milestones")
      expect(response.body).to include("Single-error volume threshold")
      expect(response.body).to include("Minimum events for one error group.")
      expect(response.body).not_to include("Project-wide error spike")
      expect(response.body).not_to include("Digest frequency")
      expect(response.body).not_to include("Error milestones")
      expect(response.body).not_to include("Project spikes")
      expect(response.body).not_to include("Spike count")
    end

    it "keeps option labels unique within each notification path" do
      sign_in users(:one)

      labels_by_path = {
        "errors" => [
          "New error groups",
          "Reopened error groups",
          "Lifetime count milestones",
          "Single-error volume threshold"
        ],
        "health" => [
          "Project-wide error spike",
          "Project p95 latency",
          "Check-in monitors"
        ],
        "workflow" => [
          "Workflow emails",
          "Environment match",
          "Severity match",
          "Status match"
        ],
        "reports" => [
          "Digest frequency",
          "Digest send hour",
          "Email schedule time zone"
        ],
        "delivery" => [
          "Hourly immediate email limit",
          "Email schedule time zone",
          "Pause immediate email during quiet hours"
        ],
        "operations" => [
          "Deployment summary emails",
          "Intake and quota warnings",
          "Retention and archive failures"
        ]
      }

      labels_by_path.each do |path, labels|
        get settings_project_path(projects(:one), section: "notifications", notification_path: path)

        labels.each do |label|
          expect(response.body.scan(label).size).to eq(1), "#{label.inspect} should appear once on #{path}"
        end
      end
    end

    it "does not load GitHub integration state for the notifications tab" do
      sign_in users(:one)

      expect(ProjectGithubIntegrationState).not_to receive(:new)

      get settings_project_path(projects(:one), section: "notifications")

      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /notification_preferences/unsubscribe/:token" do
    it "disables project email notifications without requiring a signed-in user" do
      preference = create(:project_notification_preference, :daily)

      post unsubscribe_notification_preferences_path(token: preference.unsubscribe_token)

      expect(response).to have_http_status(:ok)
      expect(preference.reload.first_occurrence_enabled).to be false
      expect(preference.regression_enabled).to be false
      expect(preference.monitor_alerts_enabled).to be false
      expect(preference.digest_frequency).to eq("none")
    end
  end
end

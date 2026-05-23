# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project retention policies", type: :request do
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

      expect(response).to redirect_to(settings_project_path(project, anchor: "retention"))
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

    it "does not allow shared members to update retention settings" do
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

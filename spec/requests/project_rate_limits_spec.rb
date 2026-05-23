# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project rate limits", type: :request do
  around do |example|
    original = ENV["LOGISTER_ADMIN_EMAILS"]
    example.run
  ensure
    ENV["LOGISTER_ADMIN_EMAILS"] = original
  end

  describe "PATCH /projects/:uuid/rate_limit" do
    it "allows app admins to set overrides for projects they do not own" do
      ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
      sign_in users(:one)
      project = projects(:two)

      patch project_rate_limit_path(project), params: {
        project: {
          public_api_rate_limit_requests_override: "2400",
          public_api_rate_limit_period_seconds_override: "120",
          public_api_auth_failure_rate_limit_requests_override: "240"
        }
      }

      expect(response).to redirect_to(settings_project_path(project, anchor: "rate-limits"))
      expect(project.reload.public_api_rate_limit_requests_override).to eq(2400)
      expect(project.public_api_rate_limit_period_seconds_override).to eq(120)
      expect(project.public_api_auth_failure_rate_limit_requests_override).to eq(240)
    end

    it "clears overrides when app admins submit blank values" do
      ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
      sign_in users(:one)
      project = projects(:two)
      project.update!(
        public_api_rate_limit_requests_override: 2400,
        public_api_rate_limit_period_seconds_override: 120,
        public_api_auth_failure_rate_limit_requests_override: 240
      )

      patch project_rate_limit_path(project), params: {
        project: {
          public_api_rate_limit_requests_override: "",
          public_api_rate_limit_period_seconds_override: "",
          public_api_auth_failure_rate_limit_requests_override: ""
        }
      }

      expect(response).to redirect_to(settings_project_path(project, anchor: "rate-limits"))
      expect(project.reload.public_api_rate_limit_requests_override).to be_nil
      expect(project.public_api_rate_limit_period_seconds_override).to be_nil
      expect(project.public_api_auth_failure_rate_limit_requests_override).to be_nil
    end

    it "does not allow project owners who are not app admins to set overrides" do
      ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
      sign_in users(:two)
      project = projects(:two)

      expect {
        patch project_rate_limit_path(project), params: {
          project: {
            public_api_rate_limit_requests_override: "2400",
            public_api_rate_limit_period_seconds_override: "120",
            public_api_auth_failure_rate_limit_requests_override: "240"
          }
        }
      }.not_to change { project.reload.public_api_rate_limit_requests_override }

      expect(response).to redirect_to(root_path)
    end
  end
end

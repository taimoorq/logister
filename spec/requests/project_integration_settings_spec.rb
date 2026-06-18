# frozen_string_literal: true

require "rails_helper"
require "cgi"

RSpec.describe "Project integration settings", type: :request do
  describe "PATCH /projects/:uuid/integration_setting" do
    it "updates an owned Cloudflare Pages project setting" do
      project = create(:project, :cloudflare_pages, user: users(:one))
      sign_in users(:one)

      patch project_integration_setting_path(project), params: {
        project_integration_setting: {
          provider: "cloudflare_pages",
          enabled: "1",
          account_id: " account-123 ",
          external_project_name: " marketing-site ",
          external_project_id: "pages-project-id",
          credential_reference: " CLOUDFLARE_API_TOKEN "
        }
      }

      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "platform-integration"))
      setting = ProjectIntegrationSetting.find_by!(project: project, provider: "cloudflare_pages")
      expect(setting).to be_enabled
      expect(setting.account_id).to eq("account-123")
      expect(setting.external_project_name).to eq("marketing-site")
      expect(setting.external_project_id).to eq("pages-project-id")
      expect(setting.credential_reference).to eq("CLOUDFLARE_API_TOKEN")
    end

    it "renders settings with validation errors" do
      project = create(:project, :cloudflare_pages, user: users(:one))
      sign_in users(:one)

      patch project_integration_setting_path(project), params: {
        project_integration_setting: {
          provider: "cloudflare_pages",
          enabled: "1",
          account_id: "",
          external_project_name: "",
          credential_reference: "CLOUDFLARE_API_TOKEN"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Cloudflare Pages connection")
      expect(CGI.unescapeHTML(response.body)).to include("Account can't be blank")
    end

    it "does not allow shared members to update platform settings" do
      project = create(:project, :cloudflare_pages, user: users(:one))
      create(:project_membership, project: project, user: users(:two))
      sign_in users(:two)

      patch project_integration_setting_path(project), params: {
        project_integration_setting: {
          provider: "cloudflare_pages",
          enabled: "1",
          account_id: "account-123",
          external_project_name: "marketing-site",
          credential_reference: "CLOUDFLARE_API_TOKEN"
        }
      }

      expect(response).to have_http_status(:not_found)
      expect(ProjectIntegrationSetting.where(project: project)).to be_empty
    end
  end

  describe "GET /projects/:uuid/settings" do
    it "shows the Cloudflare Pages connection form for owned Cloudflare projects" do
      project = create(:project, :cloudflare_pages, user: users(:one))
      sign_in users(:one)

      get settings_project_path(project, section: "integrations")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Cloudflare Pages connection")
      expect(response.body).to include("CLOUDFLARE_API_TOKEN")
    end
  end
end

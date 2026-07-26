# frozen_string_literal: true

require "rails_helper"
require "cgi"

RSpec.describe "Project integration settings", type: :request do
  include ActiveJob::TestHelper
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

    it "allows project admins to update platform settings" do
      project = create(:project, :cloudflare_pages, user: users(:one))
      create(:project_membership, project: project, user: users(:two), role: :admin)
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

      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "platform-integration"))
      expect(ProjectIntegrationSetting.find_by!(project: project)).to be_enabled
    end

    it "does not allow viewers to update platform settings" do
      project = create(:project, :cloudflare_pages, user: users(:one))
      create(:project_membership, project: project, user: users(:two), role: :viewer)
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

    it "configures Google Play only for an Android project and preserves allowed tracks" do
      project = create(:project, :android, user: users(:one))
      sign_in users(:one)

      patch project_integration_setting_path(project), params: {
        project_integration_setting: {
          provider: "google_play",
          enabled: "1",
          external_project_id: "com.acme.shop",
          credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS",
          metadata: { track_allowlist: %w[internal production] }
        }
      }

      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "google-play-integration"))
      setting = project.integration_settings.find_by!(provider: "google_play")
      expect(setting).to be_configured
      expect(setting.metadata["track_allowlist"]).to eq(%w[internal production])
    end

    it "stores App Store Connect secret references only for an iOS project" do
      project = create(:project, :ios, user: users(:one))
      sign_in users(:one)

      patch project_integration_setting_path(project), params: {
        project_integration_setting: {
          provider: "app_store_connect",
          enabled: "1",
          external_project_id: "com.acme.shop",
          account_id: "issuer-123",
          external_project_name: "KEY123",
          credential_reference: "APP_STORE_CONNECT_PRIVATE_KEY"
        }
      }

      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "app-store-connect-integration"))
      setting = project.integration_settings.find_by!(provider: "app_store_connect")
      expect(setting).to be_configured
      expect(setting.credential_reference).to eq("APP_STORE_CONNECT_PRIVATE_KEY")
    end
  end

  describe "POST /projects/:uuid/integration_setting/import" do
    it "queues the source-specific App Store Connect importer" do
      project = create(:project, :ios, user: users(:one))
      setting = create(
        :project_integration_setting,
        project: project,
        provider: "app_store_connect",
        enabled: true,
        external_project_id: "com.acme.shop",
        account_id: "issuer-123",
        external_project_name: "KEY123",
        credential_reference: "APP_STORE_CONNECT_PRIVATE_KEY"
      )
      sign_in users(:one)

      expect do
        post project_integration_setting_import_path(project, provider: "app_store_connect")
      end.to have_enqueued_job(AppStoreConnectImportJob).with(setting.id)

      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "app-store-connect-integration"))
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

    it "shows the Cloudflare Pages connection form for project admins" do
      project = create(:project, :cloudflare_pages, user: users(:one))
      create(:project_membership, project: project, user: users(:two), role: :admin)
      sign_in users(:two)

      get settings_project_path(project, section: "integrations")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Cloudflare Pages connection")
    end

    it "shows explicit Google Play provenance and R8 mapping states for Android projects" do
      project = create(:project, :android, user: users(:one))
      sign_in users(:one)

      get settings_project_path(project, section: "integrations")

      expect(response).to have_http_status(:success)
      expect(response.body).to include(
        "Google Play Developer Reporting",
        "Play metrics remain separate from Logister SDK impact",
        "No external metrics have been imported",
        "R8 / ProGuard mappings",
        "No R8 mappings uploaded"
      )
    end

    it "shows the reusable App Store Connect boundary for iOS projects" do
      project = create(:project, :ios, user: users(:one))
      sign_in users(:one)

      get settings_project_path(project, section: "integrations")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("App Store Connect", "APP_STORE_CONNECT_PRIVATE_KEY", "dSYM coverage", "No dSYM artifacts uploaded", "No App Store metrics imported")
    end
  end
end

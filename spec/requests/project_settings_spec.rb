# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Project settings", type: :request do
  describe "GET /projects/:uuid/settings" do
    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "returns success and shows focused project settings" do
        get settings_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Project identity")
        expect(response.body).to include("General", "Notifications", "Team", "Integrations", "Data", "Danger")
        expect(response.body).not_to include("API keys")
        expect(response.body).not_to include("Integration guide")
        expect(response.body).not_to include("Public API rate limits")
      end

      it "pins Settings at the end of the tab bar and marks it current" do
        project = projects(:one)

        get settings_project_path(project)

        document = Nokogiri::HTML.parse(response.body)
        tabs = document.at_css("nav[aria-label='Project sections']")
        active_settings_link = document.at_css("nav[aria-label='Project settings sections'] a[aria-current='page']")

        expect(document.at_css("details.project-nav-menu")).to be_nil
        expect(tabs.css("a").last["href"]).to eq(settings_project_path(project))
        expect(tabs.css("a").last["class"]).to include("project-tab-pinned")
        expect(tabs.at_css("a[aria-current='page']")["href"]).to eq(settings_project_path(project))
        expect(active_settings_link.text.strip).to eq("General")
        expect(active_settings_link["class"]).to include("settings-section-nav-link")
        expect(document.at_css(".settings-content .settings-panel")).to be_present
      end

      it "shows archived state on setup without allowing new API keys" do
        project = create(:project, :archived, user: users(:one), name: "Archived Settings App")

        get setup_project_path(project)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)

        expect(document.at_css(".project-archived-notice").text).to include("Archived project")
        expect(document.text).to include("API tokens are disabled while this project is archived")
        expect(document.at_css("input[name='api_key[name]']")).to be_nil
        expect(document.at_css("a[href='#{settings_project_path(project, section: 'danger')}']")).to be_present
        expect(document.at_css(".sidebar-action-link")["href"]).to eq(projects_path(filter: "archived"))

        project_navigation = document.at_css("nav[aria-label='Project sections']")
        settings_navigation = document.at_css("nav[aria-label='Project settings sections']")
        expect(project_navigation.at_css("a[aria-current='page']").text.strip).to eq("Settings")
        expect(settings_navigation.at_css("a[aria-current='page']").text.strip).to eq("Setup")
      end

      it "shows assignment workload counts for project members" do
        project = create(:project, user: users(:one), name: "Assigned Settings")
        member = create(:user, name: "Settings Member")
        create(:project_membership, project: project, user: member)
        create(:error_group, project: project, assignee: users(:one), assigned_by: users(:one))
        create(:error_group, project: project, assignee: member, assigned_by: users(:one))
        create(:error_group, project: project)

        get settings_project_path(project, section: "team")

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        access_table = document.at_css("#project_memberships_tbody")

        expect(document.text).to include("Open assignments", "Open issues", "Assigned", "Unassigned")
        expect(document.at_css("a[href='#{inbox_project_path(project, filter: 'unresolved', assignee: users(:one).uuid)}']").text.strip).to eq("1")
        expect(access_table.at_css("a[href='#{inbox_project_path(project, filter: 'unresolved', assignee: member.uuid)}']").text.strip).to eq("1")
      end

      it "shows JavaScript-specific integration guidance for logister-js projects" do
        project = create(:project, user: users(:one), integration_kind: "javascript", name: "Node App")

        get setup_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("JavaScript / TypeScript")
        expect(response.body).to include("First event guide", "First event checklist")
        expect(response.body).to include("logister-js")
        expect(response.body).to include("logister-js/express")
        expect(response.body).to include("controlled exception")
        expect(response.body).to include("release, route, and request identifiers")
        expect(response.body).to include("source maps")
        expect(response.body).to include("LOGISTER_RELEASE")
        expect(response.body).to include("https://logister.org/docs/integrations/javascript/")
      end

      it "shows Python-specific integration guidance for logister-python projects" do
        project = create(:project, user: users(:one), integration_kind: "python", name: "Python App")

        get setup_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Python")
        expect(response.body).to include("First event guide", "First event checklist")
        expect(response.body).to include("logister-python")
        expect(response.body).to include("instrument_fastapi")
        expect(response.body).to include("FastAPI", "Django", "Flask")
        expect(response.body).to include("https://logister.org/docs/integrations/python/")
      end

      it "shows .NET-specific integration guidance for logister-dotnet projects" do
        project = create(:project, user: users(:one), integration_kind: "dotnet", name: "QuriaTime")

        get setup_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include(".NET / ASP.NET Core")
        expect(response.body).to include("First event guide", "First event checklist")
        expect(response.body).to include("Logister.AspNetCore")
        expect(response.body).to include("AddLogister")
        expect(response.body).to include("UseLogisterExceptionReporting")
        expect(response.body).to include("LogisterClient")
        expect(response.body).to include("https://logister.org/docs/integrations/dotnet/")
      end

      it "allows app admins to view settings for projects they do not own" do
        original = ENV["LOGISTER_ADMIN_EMAILS"]
        ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email

        get settings_project_path(projects(:two), section: "admin")

        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:two).name)
        expect(response.body).to include("Public API rate limits")
        expect(response.body).to include(project_rate_limit_path(projects(:two)))

        document = Nokogiri::HTML.parse(response.body)
        project_navigation = document.at_css("nav[aria-label='Project sections']")
        expect(project_navigation.css("a").map { |link| link.text.strip }).to eq([ "Settings" ])
        expect(project_navigation.at_css("a[aria-current='page']")["href"]).to eq(settings_project_path(projects(:two)))
      ensure
        ENV["LOGISTER_ADMIN_EMAILS"] = original
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns success and shows project (read-only settings)" do
        get settings_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Project identity")
        expect(response.body).not_to include("Team")
        expect(response.body).not_to include("Integrations")
        expect(response.body).not_to include("Data")
        expect(response.body).not_to include("Danger")
      end

      it "shows management settings to project admins except danger" do
        project_memberships(:one).update!(role: :admin)

        get settings_project_path(projects(:one), section: "integrations")

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Team", "Integrations", "Data")
        expect(response.body).to include("GitHub repositories")
        expect(response.body).not_to include("Danger")
      end

      it "shows CFML-specific integration guidance for CFML projects" do
        get setup_project_path(projects(:two))
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Integration guide")
        expect(response.body).to include("CFML integration docs")
        expect(response.body).to include("Application.cfc.onError()")
        expect(response.body).to include("https://logister.org/docs/integrations/cfml/")
        expect(response.body).to include('target="_blank"')
      end
    end
  end

  describe "feature settings links" do
    let(:project) { projects(:one) }

    context "when signed in as the project owner" do
      before { sign_in users(:one) }

      it "links each browse surface to the settings that configure it" do
        expectations = [
          [ project_path(project), "Project settings", settings_project_path(project, section: "general") ],
          [ inbox_project_path(project), "Issue alerts", settings_project_path(project, section: "notifications", notification_path: "errors", anchor: "error-triage-alerts") ],
          [ activity_project_path(project), "Telemetry setup", setup_project_path(project) ],
          [ insights_project_path(project), "Telemetry setup", setup_project_path(project) ],
          [ performance_project_path(project), "Performance alerts", settings_project_path(project, section: "notifications", notification_path: "health", anchor: "performance-alerts") ],
          [ monitors_project_path(project), "Monitor alerts", settings_project_path(project, section: "notifications", notification_path: "health", anchor: "monitor-alerts") ],
          [ deployments_project_path(project), "Deployment settings", settings_project_path(project, section: "integrations", anchor: "source-repositories") ],
          [ archives_project_path(project), "Archive settings", settings_project_path(project, section: "data", anchor: "archive-center") ]
        ]

        expectations.each do |page_path, label, settings_path|
          get page_path

          expect(response).to have_http_status(:success)
          document = Nokogiri::HTML.parse(response.body)
          link = document.at_css("[data-project-feature-settings='true']")
          expect(link).to be_present
          expect(link.text.strip).to eq(label)
          expect(link["href"]).to eq(settings_path)
          expect(document.at_css(".project-command-panel [data-project-feature-settings='true']")).to be_nil
        end
      end

      it "provides stable deep-link targets for feature alert settings" do
        get settings_project_path(project, section: "notifications", notification_path: "errors")
        expect(Nokogiri::HTML.parse(response.body).at_css("#error-triage-alerts")).to be_present

        get settings_project_path(project, section: "notifications", notification_path: "health")
        document = Nokogiri::HTML.parse(response.body)
        expect(document.at_css("#performance-alerts")).to be_present
        expect(document.at_css("#monitor-alerts")).to be_present
      end
    end

    context "when signed in as a project viewer" do
      before { sign_in users(:two) }

      it "hides manager-only deployment and archive settings links" do
        get deployments_project_path(project)
        expect(Nokogiri::HTML.parse(response.body).at_css("[data-project-feature-settings='true']")).to be_nil

        get archives_project_path(project)
        expect(Nokogiri::HTML.parse(response.body).at_css("[data-project-feature-settings='true']")).to be_nil
      end

      it "keeps personal inbox notification settings accessible" do
        get inbox_project_path(project)

        link = Nokogiri::HTML.parse(response.body).at_css("[data-project-feature-settings='true']")
        expect(link.text.strip).to eq("Issue alerts")
        expect(link["href"]).to eq(settings_project_path(project, section: "notifications", notification_path: "errors", anchor: "error-triage-alerts"))
      end
    end
  end
end

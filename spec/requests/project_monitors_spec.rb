# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Project monitors", type: :request do
  describe "GET /projects/:uuid/monitors" do
    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "returns success and shows monitors page" do
        get monitors_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Cron and uptime monitors")
        expect(response.body).to include("Ruby integration docs")
        expect(response.body).to include("https://logister.org/docs/integrations/ruby/")
      end

      it "shows pause and resume controls for a project manager" do
        project = projects(:one)
        monitor = create(:check_in_monitor, project: project, slug: "billing-sync")

        get monitors_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("billing-sync", "Pause alerts")

        monitor.pause_monitoring!
        get monitors_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("paused", "Resume alerts")
      end

      it "keeps Monitors reachable and current even before a monitor exists" do
        project = create(:project, user: users(:one))

        get monitors_project_path(project)

        document = Nokogiri::HTML.parse(response.body)
        nav = document.at_css("nav[aria-label='Project sections']")

        expect(nav.css("> a").map { |link| link.text.strip }).to eq(%w[Overview Issues Performance Releases Explore Monitors Settings])
        expect(nav.at_css("a[aria-current='page']")["href"]).to eq(monitors_project_path(project))
      end

      it "lists Monitors as a tab for every project type once a monitor exists" do
        project = create(:project, user: users(:one))
        create(:check_in_monitor, project: project)

        get performance_project_path(project)

        nav = Nokogiri::HTML.parse(response.body).at_css("nav[aria-label='Project sections']")
        expect(nav.css("> a").map { |link| link.text.strip }).to include("Monitors")
      end

      { "javascript" => "JavaScript", "python" => "Python" }.each do |kind, label|
        it "shows #{label} integration docs on #{label} monitor pages" do
          project = create(:project, user: users(:one), integration_kind: kind)

          get monitors_project_path(project)

          expect(response).to have_http_status(:success)
          expect(response.body).to include("#{label} integration docs", "https://logister.org/docs/integrations/#{kind}/")
        end
      end

      it "lets a project owner pause and resume one monitor" do
        project = projects(:one)
        monitor = create(:check_in_monitor, project: project, slug: "android-widget-rotation")

        patch project_check_in_monitor_path(project, monitor), params: {
          check_in_monitor: { monitoring_state: "paused" }
        }

        expect(response).to redirect_to(monitors_project_path(project))
        expect(monitor.reload).to be_monitoring_paused

        patch project_check_in_monitor_path(project, monitor), params: {
          check_in_monitor: { monitoring_state: "active" }
        }

        expect(response).to redirect_to(monitors_project_path(project))
        expect(monitor.reload).not_to be_monitoring_paused
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns success and shows monitors page" do
        create(:check_in_monitor, project: projects(:one), slug: "viewer-monitor")

        get monitors_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Cron and uptime monitors")
        expect(response.body).not_to include("Pause alerts", "Resume alerts")
      end

      it "does not allow a viewer to change monitor state" do
        project = projects(:one)
        monitor = create(:check_in_monitor, project: project)

        patch project_check_in_monitor_path(project, monitor), params: {
          check_in_monitor: { monitoring_state: "paused" }
        }

        expect(response).to have_http_status(:not_found)
        expect(monitor.reload).not_to be_monitoring_paused
      end
    end
  end
end

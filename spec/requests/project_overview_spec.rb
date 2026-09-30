# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Project overview", type: :request do
  describe "GET /projects/:uuid" do
    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "returns success and shows project" do
        get project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
      end

      it "keeps archived projects accessible while routing project-list links back to archived projects" do
        project = create(:project, :archived, user: users(:one), name: "Archived Inbox App")

        get project_path(project)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        menu = document.at_css(".nav-project-menu")

        expect(document.at_css(".project-archived-notice").text).to include("Archived project")
        expect(document.at_css(".sidebar-action-link[href='#{projects_path(filter: 'archived')}']")).to be_present
        expect(menu.css(".nav-project-item-title").map { |node| node.text.strip }).not_to include(project.name)
      end

      it "renders a project dashboard with timeline, error group summary, and performance summary" do
        project = create(:project, user: users(:one), name: "Status Strip")
        api_key = create(:api_key, project: project, user: users(:one))
        create(:ingest_event, :grouped, project: project, api_key: api_key, message: "Grouped status error")
        create(:ingest_event, :log, project: project, api_key: api_key, occurred_at: 2.hours.ago)
        create(:ingest_event, :transaction, project: project, api_key: api_key, occurred_at: 20.minutes.ago, context: { duration_ms: 128.4 })
        create(:ingest_event, :metric, project: project, api_key: api_key, message: "db.query", occurred_at: 10.minutes.ago, context: { duration_ms: 42.5 })
        create(:check_in_monitor, :missed, project: project)

        get project_path(project)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)

        expect(document.at_css(".inbox-workbench")).to be_nil
        tour_root = document.at_css("[data-product-tour-group-value='project-overview']")
        expect(tour_root).to be_present
        expect(tour_root["data-action"]).to include("click->product-tour#startForNewUser:capture", "turbo:before-cache@document->product-tour#beforeCache")
        expect(document.at_css("nav[data-tg-group='project-overview']")).to be_present
        expect(document.at_css(".project-command-panel nav[aria-label='Project sections']")).to be_present
        expect(document.css("[data-tg-group='project-overview']").map { |node| node["data-tg-title"] }).to include(
          "Project header",
          "Project navigation",
          "Recent signals"
        )
        expect(document.at_css(".help-menu button[data-action*='click->product-tour#start']")).to be_present
        expect(document.at_css("section[aria-label='Project collection areas']")).to be_nil
        expect(document.text).not_to include("Events and logs", "View events")
        expect(document.text).not_to include("Recent errors", "Newest unresolved groups")
        expect(document.at_css("a[href='#{inbox_project_path(project, filter: 'unresolved')}']").text).to include("1", "Open")
        expect(document.at_css("a[href='#{inbox_project_path(project, filter: 'introduced_today')}']").text).to include("New today")
        expect(document.at_css("a[href='#{inbox_project_path(project, filter: 'all')}']").text).to include("All groups")
        expect(document.css("a[href='#{performance_project_path(project)}']").map(&:text).join(" ")).to include("View performance")
        expect(document.text).to include("Performance", "Transactions", "DB queries", "1")
        timeline = document.at_css("[data-controller='project-insights']")
        expect(timeline).to be_present
        chart = timeline.at_css(".project-insights-chart-main[role='img']")
        expect(chart).to be_present
        expect(timeline.at_css("a[href='#{insights_project_path(project)}']").text).to eq("Insights")
        expect(document.text).to include("Telemetry timeline", "Counts, durations, and custom values in the current scope")
        expect(document.text).to include("Add chart series")
        expect(document.text).to include("Issues", "Error groups")
        expect(document.css("a[href='#{inbox_project_path(project)}']").map(&:text).join(" ")).to include("Issues")
        aside = document.at_css("aside.dashboard-panel")
        expect(aside.at_css("section[aria-label='Project error groups summary']")).to be_present
        expect(aside.at_css("section[aria-label='Project performance summary']")).to be_present
        expect(aside.text).to include("Error groups", "Performance", "Request timing")
        expect(document.text).not_to include("Latest collection")
        timeline_payload = JSON.parse(timeline["data-project-insights-payload-value"])
        expect(timeline_payload.fetch("endpoint")).to eq(insights_data_project_path(project))
        expect(timeline_payload.fetch("default_window")).to eq(ProjectInsights::DEFAULT_WINDOW)
        expect(timeline_payload.fetch("default_metrics")).to eq(ProjectInsights.default_metric_keys)
        expect(timeline_payload.fetch("storage_key")).to eq("logister.project-overview-insights.#{project.uuid}")
      end
    end
  end
end

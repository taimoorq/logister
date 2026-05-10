# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Dashboard", type: :request do
  describe "GET /dashboard" do
    it "requires authentication" do
      get dashboard_path
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in" do
      before { sign_in users(:one) }

      it "returns success" do
        get dashboard_path
        expect(response).to have_http_status(:success)
      end

      it "shows overview content and project count" do
        get dashboard_path
        expect(response.body).to include(projects(:one).name)
      end

      it "does not include archived projects in active dashboard data" do
        archived_project = create(:project, :archived, user: users(:one), name: "Archived Dashboard App")

        get dashboard_path

        expect(response.body).not_to include(archived_project.name)
      end

      it "renders overview cards and compact project shortcuts" do
        project = projects(:one)
        create(:ingest_event, :log, project: project, api_key: api_keys(:one), occurred_at: 30.minutes.ago)

        get dashboard_path

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        project_row = document.css(".dashboard-project-row").find { |node| node.text.include?(project.name) }
        project_overview = document.at_css(".dashboard-project-overview-grid")

        expect(document.at_css(".dashboard-page")).to be_present
        expect(document.at_css(".dashboard-title-row .dashboard-title-metrics")).to be_nil
        expect(project_overview).to be_present
        expect(project_overview.css(".dashboard-title-metrics > span").size).to eq(4)
        expect(document.at_css(".projects-search input[aria-label='Search projects']")).to be_nil
        expect(project_overview.css(".dashboard-metric-card").size).to eq(4)
        expect(project_overview.at_css(".dashboard-project-summary-panel")).to be_present
        expect(project_overview.at_css(".dashboard-project-overview-main")).to be_present
        expect(document.at_css("a.projects-new-button")["href"]).to eq(new_project_path)
        expect(document.at_css("a[href='#{projects_path}']")).to be_present
        expect(document.text).to include("Needs attention", "Event mix", "Projects at a glance")
        expect(document.text).not_to include("Recent activity")
        expect(document.at_css("[data-controller='dashboard-attention']")).to be_present
        expect(document.css(".dashboard-event-mix-row[data-dashboard-attention-target='filter']").size).to eq(Dashboard::EVENT_TYPE_ORDER.size)
        expect(document.at_css(".dashboard-attention-row[data-event-type='error']")).to be_present
        expect(document.at_css(".dashboard-attention-row-context")).to be_present
        expect(document.at_css(".project-card")).to be_nil
        expect(project_row).to be_present
        expect(project_row.at_css(".dashboard-project-main")["href"]).to eq(project_path(project))
        expect(project_row.at_css(".project-type-icon-ruby use")["href"]).to match(%r{streamline-freehand(?:-[a-f0-9]+)?\.svg#streamline-project-ruby\z})
        expect(project_row.at_css("a[href='#{project_path(project, filter: 'unresolved')}']")).to be_present
        expect(project_row.at_css("a[href='#{activity_project_path(project)}']")).to be_present
      end

      it "renders the server-backed dashboard explorer shell" do
        get dashboard_path

        document = Nokogiri::HTML.parse(response.body)
        explorer = document.at_css("[data-controller='dashboard-explorer']")
        payload = JSON.parse(explorer["data-dashboard-explorer-payload-value"])

        expect(explorer).to be_present
        expect(explorer.at_css("script[data-dashboard-explorer-target='payload']")).to be_nil
        expect(explorer.at_css(".dashboard-explorer-slice[aria-label='Current explorer slice']")).to be_present
        expect(explorer.at_css(".dashboard-explorer-summary[data-dashboard-explorer-target='summary']")).to be_present
        expect(explorer.at_css(".dashboard-explorer-filters[data-dashboard-explorer-target='filters']")).to be_present
        expect(payload["endpoint"]).to eq(dashboard_explorer_path)
        expect(payload["window_days"]).to eq(Dashboard::EXPLORER_WINDOW_DAYS)
        expect(payload["rows"]).to be_nil
        expect(document.css("[data-dashboard-explorer-target$='Chart']").size).to eq(4)
      end

      it "returns filtered explorer aggregates as JSON" do
        project = projects(:one)
        create(:ingest_event, :log, project: project, api_key: api_keys(:one), context: { "environment" => "production" }, occurred_at: 30.minutes.ago)

        get dashboard_explorer_path, params: { event_type: "log", project_id: project.id, environment: "production" }

        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq("application/json")

        data = JSON.parse(response.body)

        expect(data.dig("totals", "events")).to be >= 1
        expect(data["days"]).to be_an(Array)
        expect(data["days"].size).to eq(Dashboard::EXPLORER_WINDOW_DAYS)
        expect(data["event_types"].find { |event_type| event_type["key"] == "log" }["count"]).to be >= 1
        expect(data["projects"].map { |project_row| project_row["id"] }).to include(project.id)
        expect(data["environments"]).to include(hash_including("name" => "production"))
      end

      it "bounds arbitrary environment filters before querying" do
        get dashboard_explorer_path, params: { environment: "x" * 500 }

        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq("application/json")
      end
    end
  end
end

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

      it "uses the dark-nav logo without flattening the icon colors" do
        get dashboard_path

        document = Nokogiri::HTML.parse(response.body)
        logo = document.at_css("nav img[alt='Logister']")

        expect(logo).to be_present
        expect(logo["src"]).to include("logister-logo-light")
        expect(logo["class"]).not_to include("brightness-0")
        expect(logo["class"]).not_to include("invert")
      end

      it "loads npm-backed tour assets and renders the dashboard tour affordance" do
        get dashboard_path

        document = Nokogiri::HTML.parse(response.body)
        importmap = document.at_css("script[type='importmap']").text
        module_script = document.at_css("script[type='module']")
        preload_hrefs = document.css("link[rel='modulepreload']").map { |node| node["href"].to_s }

        expect(document.at_css("link[href*='css/tour.min']")).to be_present
        expect(document.at_css("script[src*='tour'][defer]")).to be_present
        expect(module_script&.text).to include('import "authenticated"')
        expect(preload_hrefs.grep(/entrypoints\/(?:public|auth)\b/)).to be_empty
        expect(importmap).to include("echarts", "echarts.esm.min")
        tour_root = document.at_css(".dashboard-page[data-controller='product-tour'][data-product-tour-group-value='dashboard']")
        expect(tour_root).to be_present
        expect(tour_root["data-action"]).to include("click->product-tour#startForNewUser:capture", "turbo:before-cache@document->product-tour#beforeCache")
        expect(document.at_css(".tour-help-button[data-action='click->product-tour#start']")).to be_present
        expect(document.at_css(".tour-help-button .tour-help-button-mark")&.text).to eq("?")
        expect(document.css("[data-tg-group='dashboard']").map { |node| node["data-tg-title"] }).to include("Dashboard overview", "Explorer", "Attention queue")

        get dashboard_path(tab: "projects")

        document = Nokogiri::HTML.parse(response.body)
        expect(document.css("[data-tg-group='dashboard']").map { |node| node["data-tg-title"] }).to include("Project signals")
      end

      it "renders active accessible projects in the top navigation dropdown" do
        active_project = create(:project, :python, user: users(:one), name: "Alpha Nav App")
        shared_project = create(:project, :dotnet, user: users(:two), name: "Shared Nav App")
        archived_project = create(:project, :archived, user: users(:one), name: "Archived Nav App")
        create(:project_membership, project: shared_project, user: users(:one))

        get dashboard_path

        document = Nokogiri::HTML.parse(response.body)
        menu = document.at_css(".nav-project-menu")

        expect(menu).to be_present

        project_names = menu.css(".nav-project-item-title").map { |node| node.text.strip }

        expect(menu.at_css("summary").text).to include("Projects")
        expect(project_names).to include(projects(:one).name, active_project.name, shared_project.name)
        expect(project_names).not_to include(archived_project.name)
        expect(menu.at_css("a[href='#{project_path(active_project)}']")).to be_present
        expect(menu.at_css("a[href='#{project_path(shared_project)}']")).to be_present
        expect(menu.at_css("a[href='#{projects_path}']")).to be_present
        expect(menu.at_css(".nav-project-action-primary")["href"]).to eq(new_project_path)
      end

      it "renders a dismissible release update notification in the top navigation" do
        update = Logister::ReleaseUpdateChecker::Result.new(
          current_version: "2.1.0",
          latest_version: "2.1.1",
          release_name: "Logister v2.1.1",
          release_url: "https://github.com/taimoorq/logister/releases/tag/v2.1.1",
          published_at: "2026-05-22T22:00:00Z"
        )
        allow(Logister::ReleaseUpdateChecker).to receive(:call).and_return(update)

        get dashboard_path

        document = Nokogiri::HTML.parse(response.body)
        notification_menu = document.css("details").find { |node| node.at_css("summary")&.text&.include?("Notifications") || node.at_css("summary[aria-label='1 notification available']") }

        expect(notification_menu).to be_present
        expect(notification_menu.text).to include("Update available")
        expect(notification_menu.text).to include("Logister v2.1.1 is available. This instance is running v2.1.0.")
        expect(notification_menu.at_css("a[href='https://github.com/taimoorq/logister/releases/tag/v2.1.1']")).to be_present
        expect(notification_menu.at_css("form[action='#{dismiss_notification_path(notification_key: update.notification_key)}']")).to be_present

        post dismiss_notification_path, params: { notification_key: update.notification_key }

        expect(response).to redirect_to(dashboard_path)
        expect(users(:one).user_notification_dismissals.exists?(notification_key: update.notification_key)).to eq(true)

        get dashboard_path

        expect(response.body).not_to include("Logister v2.1.1 is available")
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

      it "renders the overview tab and project shortcuts tab" do
        project = projects(:one)
        create(:ingest_event, :log, project: project, api_key: api_keys(:one), occurred_at: 30.minutes.ago)

        get dashboard_path

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        tabs = document.at_css(".dashboard-tabs[role='tablist']")
        active_tab = tabs.at_css(".dashboard-tab.is-active[aria-selected='true']")
        overview_panel = document.at_css("#dashboard-tab-overview.dashboard-overview-layout")
        priority_grid = overview_panel.at_css(".dashboard-priority-grid")
        explorer = overview_panel.at_css(".dashboard-explorer")

        expect(document.at_css(".dashboard-page")).to be_present
        expect(document.at_css(".dashboard-title-row .dashboard-title-metrics")).to be_nil
        expect(tabs).to be_present
        expect(active_tab.text.strip).to eq("Overview")
        expect(tabs.at_css("a[href='#{dashboard_path(tab: "projects")}']")).to be_present
        expect(overview_panel).to be_present
        expect(document.at_css("#dashboard-tab-projects")).to be_nil
        expect(document.at_css(".projects-search input[aria-label='Search projects']")).to be_nil
        expect(document.at_css("a.projects-new-button")["href"]).to eq(new_project_path)
        expect(document.at_css("a[href='#{projects_path}']")).to be_present
        expect(document.text).to include("Needs attention")
        expect(document.text).to include("My assignments")
        expect(document.text).not_to include("Event mix", "Projects at a glance")
        expect(document.text).not_to include("Recent activity")
        expect(document.at_css(".dashboard-project-overview-grid")).to be_nil
        expect(document.at_css("[data-controller='dashboard-attention']")).to be_present
        expect(document.css(".dashboard-priority-grid").size).to eq(1)
        expect(priority_grid).to be_present
        expect(overview_panel.at_xpath("./*[contains(concat(' ', normalize-space(@class), ' '), ' dashboard-explorer ')]")).to be_present
        expect(overview_panel.at_xpath("./*[contains(concat(' ', normalize-space(@class), ' '), ' dashboard-priority-grid ')]")).to be_present
        expect(priority_grid.at_xpath("./*[contains(concat(' ', normalize-space(@class), ' '), ' dashboard-assignment-panel ')]")).to be_present
        expect(priority_grid.to_html.index("dashboard-assignment-panel")).to be < priority_grid.to_html.index("dashboard-attention-panel")
        expect(explorer).to be_present
        expect(document.at_css(".dashboard-event-mix-row[data-dashboard-attention-target='filter']")).to be_nil
        expect(document.at_css(".dashboard-attention-row[data-event-type='error']")).to be_present
        expect(document.at_css(".dashboard-attention-row-context")).to be_present
        expect(document.at_css(".project-card")).to be_nil

        get dashboard_path(tab: "projects")

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        project_row = document.css(".dashboard-project-row").find { |node| node.text.include?(project.name) }
        project_overview = document.at_css(".dashboard-project-overview-grid")
        active_tab = document.at_css(".dashboard-tab.is-active[aria-selected='true']")

        expect(active_tab.text.strip).to eq("Projects")
        expect(document.at_css("#dashboard-tab-overview")).to be_nil
        expect(document.at_css("#dashboard-tab-projects")).to be_present
        expect(document.at_css("[data-controller='dashboard-attention']")).to be_nil
        expect(document.at_css("[data-controller='dashboard-explorer']")).to be_nil
        expect(project_overview).to be_present
        expect(project_overview.css(".dashboard-title-metrics > span").size).to eq(4)
        expect(project_overview.css(".dashboard-metric-card").size).to eq(4)
        expect(project_overview.at_css(".dashboard-project-summary-panel")).to be_present
        expect(project_overview.at_css(".dashboard-project-overview-main")).to be_present
        expect(document.text).to include("Projects at a glance", "Project signals")
        expect(document.text).not_to include("Event mix")
        expect(project_row).to be_present
        expect(project_row.at_css(".dashboard-project-main")["href"]).to eq(project_path(project))
        expect(project_row.at_css(".project-type-icon-ruby use")["href"]).to match(%r{streamline-freehand(?:-[a-f0-9]+)?\.svg#streamline-project-ruby\z})
        expect(project_row.at_css("a[href='#{inbox_project_path(project, filter: 'unresolved')}']")).to be_present
        expect(project_row.at_css("a[href='#{activity_project_path(project)}']")).to be_present
      end

      it "shows assigned-to-me bugs as account-wide dashboard shortcuts" do
        project = projects(:one)
        group = create(:error_group,
                       project: project,
                       assignee: users(:one),
                       assigned_by: users(:one),
                       title: "Assigned checkout failure")

        get dashboard_path

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        panel = document.at_css(".dashboard-assignment-panel")
        row = panel.at_css("a[href='#{inbox_project_path(project, group_uuid: group.uuid, assignee: 'me')}']")

        expect(panel).to be_present
        expect(panel.text).to include("My assignments", "Assigned checkout failure")
        expect(panel.text).to include("Assigned to me")
        expect(row).to be_present
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
        expect(explorer.at_css(".dashboard-explorer-open[data-dashboard-explorer-target='openEventsLink']")["href"]).to eq(dashboard_events_path)
        expect(explorer.at_css(".dashboard-explorer-project[data-dashboard-explorer-target='openProjectLink'][hidden]")).to be_present
        expect(payload["endpoint"]).to eq(dashboard_explorer_path)
        expect(payload["events_endpoint"]).to eq(dashboard_events_path)
        expect(payload["window_days"]).to eq(Dashboard::EXPLORER_WINDOW_DAYS)
        expect(payload["projects"]).to include(hash_including("name" => projects(:one).name, "url" => project_path(projects(:one))))
        expect(payload["rows"]).to be_nil
        expect(explorer.css("[data-dashboard-explorer-target$='Chart']").size).to eq(3)
        expect(explorer.at_css("[data-dashboard-explorer-target='environmentChart']")).to be_nil
      end

      it "returns filtered explorer aggregates as JSON" do
        travel_to Time.zone.local(2026, 5, 10, 12, 0, 0) do
          project = projects(:one)
          create(:ingest_event, :log, project: project, api_key: api_keys(:one), context: { "environment" => "production" }, occurred_at: 30.minutes.ago)

          occurred_on = Time.current.to_date.iso8601
          get dashboard_explorer_path, params: { event_type: "log", project_id: project.id, environment: "production", occurred_on: occurred_on }

          expect(response).to have_http_status(:success)
          expect(response.media_type).to eq("application/json")

          data = JSON.parse(response.body)

          expect(data.dig("totals", "events")).to be >= 1
          expect(data["days"]).to be_an(Array)
          expect(data["days"]).to eq([ occurred_on ])
          expect(data["events_url"]).to include(dashboard_events_path)
          expect(data["events_url"]).to include("event_type=log")
          expect(data["events_url"]).to include("project_id=#{project.id}")
          expect(data["events_url"]).to include("environment=production")
          expect(data["events_url"]).to include("occurred_on=#{occurred_on}")
          expect(data["event_types"].find { |event_type| event_type["key"] == "log" }["count"]).to be >= 1
          project_row = data["projects"].find { |row| row["id"] == project.id }
          expect(project_row).to include("url" => project_path(project), "activity_url" => activity_project_path(project))
          expect(data["environments"]).to include(hash_including("name" => "production"))
        end
      end

      it "renders account-wide matching events for an explorer slice" do
        travel_to Time.zone.local(2026, 5, 10, 12, 0, 0) do
          project = projects(:one)
          other_project = create(:project, user: users(:two), name: "Hidden Events App")
          other_key = create(:api_key, project: other_project, user: users(:two))
          matching_event = create(:ingest_event,
                                  :log,
                                  project: project,
                                  api_key: api_keys(:one),
                                  message: "checkout worker lagged",
                                  context: { "environment" => "production", "release" => "2026.05.10" },
                                  occurred_at: 30.minutes.ago)
          create(:ingest_event,
                 :log,
                 project: other_project,
                 api_key: other_key,
                 message: "private service event",
                 context: { "environment" => "production" },
                 occurred_at: 20.minutes.ago)

          get dashboard_events_path, params: { event_type: "log", project_id: project.id, environment: "production", occurred_on: "2026-05-10" }

          expect(response).to have_http_status(:success)

          document = Nokogiri::HTML.parse(response.body)
          event_link = document.at_css(
            "a[href='#{project_event_path(project, matching_event, event_occurred_at: matching_event.occurred_at.utc.iso8601(6))}']"
          )

          expect(document.text).to include("Matching events", "checkout worker lagged", project.name, "Logs", "production", "2026.05.10")
          expect(document.text).not_to include("private service event", "Hidden Events App")
          expect(event_link).to be_present
        end
      end

      it "bounds arbitrary environment filters before querying" do
        get dashboard_explorer_path, params: { environment: "x" * 500 }

        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq("application/json")
      end
    end
  end
end

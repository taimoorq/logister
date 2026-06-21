# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Projects", type: :request do
  describe "GET /projects" do
    it "requires authentication" do
      get projects_path
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "returns success and lists projects" do
        get projects_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Ruby gem")
        expect(response.body).to include("Active apps")
        expect(response.body).to include("Events 7d")
        expect(response.body).to include("Active", "Archived", "All")
        expect(response.body).to include(">Docs<")
        expect(response.body).to include("Open the docs")
        expect(response.body).to include("https://docs.logister.org/")
        expect(response.body).to include('target="_blank"')
        expect(response.body).to include('rel="noopener noreferrer"')
      end

      it "renders Bugsnag-style project cards with clickable headers and counts" do
        project = create(:project, :dotnet, user: users(:one), name: "quria-work")
        api_key = create(:api_key, project: project, user: users(:one))
        create(:ingest_event, :transaction, project: project, api_key: api_key)
        create(:ingest_event, :log, project: project, api_key: api_key)

        get projects_path

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        card = document.css(".project-card").find { |node| node.text.include?("quria-work") }

        expect(card).to be_present
        expect(card.at_css(".project-card-header")["href"]).to eq(project_path(project))
        expect(card.at_css(".project-type-icon-dotnet use")["href"]).to match(%r{streamline-freehand(?:-[a-f0-9]+)?\.svg#streamline-project-dotnet\z})
        expect(card.at_css(".project-card-health")).to be_nil
        expect(card.text).not_to include("Session stability", "User stability", "Performance score")

        open_errors_link = card.at_css("a[href='#{inbox_project_path(project, filter: 'unresolved')}']")
        all_errors_link = card.at_css("a[href='#{inbox_project_path(project, filter: 'all')}']")
        activity_link = card.at_css("a[href='#{activity_project_path(project)}']")

        expect(open_errors_link).to be_present
        expect(open_errors_link.text).to include("Errors for review", "0", "No open errors")
        expect(all_errors_link).to be_present
        expect(all_errors_link.text).to include("All error groups", "0", "No errors yet")
        expect(activity_link).to be_present
        expect(activity_link.text).to include("Events 7d", "2", "View events")
        expect(card.at_css(".project-card-line-chart")).to be_present
        expect(card.text).to include("No open errors")
      end

      it "hides archived projects from the default list and shows them from the archived filter" do
        archived_project = create(:project, :archived, user: users(:one), name: "Resting App")
        create(:error_group, project: archived_project)

        get projects_path

        expect(response.body).not_to include("Resting App")

        get projects_path(filter: "archived")

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Resting App", "Archived apps")

        document = Nokogiri::HTML.parse(response.body)
        card = document.css(".project-card.is-archived").find { |node| node.text.include?(archived_project.name) }

        expect(card).to be_present
        expect(card.text).to include("Archived")
        expect(document.at_css(".projects-overview-strip a[href='#{dashboard_path}']")).to be_nil
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "includes shared project in list" do
        get projects_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
      end
    end
  end

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
        expect(document.at_css(".project-command-actions nav[aria-label='Project sections']")).to be_present
        expect(document.css("[data-tg-group='project-overview']").map { |node| node["data-tg-title"] }).to include(
          "Project header",
          "Project navigation",
          "Recent signals"
        )
        expect(document.at_css(".tour-help-button[data-action='click->product-tour#start']")).to be_present
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
        expect(document.text).to include("Inbox", "Error groups")
        expect(document.css("a[href='#{inbox_project_path(project)}']").map(&:text).join(" ")).to include("Inbox")
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

      it "points activity-only .NET projects from the empty inbox to Events" do
        project = create(:project, :dotnet, user: users(:one), name: "quria-work")
        api_key = create(:api_key, project: project, user: users(:one))
        create(:ingest_event, :transaction, project: project, api_key: api_key)

        get inbox_project_path(project)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        inbox = document.at_css("turbo-frame#project_inbox")

        expect(inbox.text).to include("No errors matching this filter")
        expect(inbox.text).to include("Those live in")
        expect(inbox.at_css("a[href='#{activity_project_path(project)}']").text).to eq("Events")
      end

      it "returns 404 for project user cannot access" do
        get project_path(projects(:two))
        expect(response).to have_http_status(:not_found)
      end

      it "renders the selected group's latest event in the inbox detail pane" do
        project = create(:project, user: users(:one), integration_kind: "python", name: "Python Inbox")
        api_key = create(:api_key, user: users(:one), project: project, name: "python-inbox")
        latest_event = create(:ingest_event,
                              project: project,
                              api_key: api_key,
                              event_type: :error,
                              message: "Latest grouped error",
                              fingerprint: "python-inbox-error")
        error_group = ErrorGroup.create!(
          project: project,
          latest_event: latest_event,
          fingerprint: "python-inbox-error",
          title: "Latest grouped error",
          status: :unresolved,
          first_seen_at: latest_event.occurred_at,
          last_seen_at: latest_event.occurred_at,
          occurrence_count: 1
        )
        latest_event.update!(error_group: error_group)
        ErrorOccurrence.create!(error_group: error_group, ingest_event: latest_event, occurred_at: latest_event.occurred_at)

        get inbox_project_path(project, group_uuid: error_group.uuid)

        expect(response).to have_http_status(:success)
        detail_frame = Nokogiri::HTML.parse(response.body).at_css('turbo-frame#error_detail')

        expect(detail_frame).to be_present
        expect(detail_frame.text).to include("Latest grouped error")
        expect(detail_frame.text).to include("Related logs")
        expect(detail_frame.text).to include("Export JSON", "Include latest 50 occurrences")
        export_form = detail_frame.at_css("form[action='#{export_project_error_group_path(project, error_group)}'][data-turbo='false']")
        expect(export_form).to be_present
        expect(export_form["data-controller"]).to eq("error-export")
        expect(export_form["data-action"]).to include("submit->error-export#download")
        expect(export_form["data-error-export-filename"]).to eq("logister-error-#{error_group.uuid}.json")
        expect(export_form["target"]).to eq("_top")
        expect(export_form.at_css("input[type='checkbox'][name='include_occurrences'][value='1']")).to be_present
        expect(export_form.at_css("button[data-error-export-target='button']")).to be_present
      end

      it "marks the active filter and selected inbox row with accessible state attributes" do
        get inbox_project_path(projects(:system_inbox), filter: "unresolved", group_uuid: error_groups(:system_primary_group).uuid)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        active_filter = document.at_css(".inbox-filter-link[aria-current='page']")
        selected_row = document.at_css("tr.inbox-row[aria-selected='true']")

        expect(active_filter).to be_present
        expect(active_filter.text).to include("Open")
        expect(selected_row).to be_present
        expect(selected_row["id"]).to eq(ActionView::RecordIdentifier.dom_id(error_groups(:system_primary_group)))
      end

      it "renders the inbox controls as a top filter bar and uses compact row metadata" do
        get inbox_project_path(projects(:system_inbox), filter: "unresolved", group_uuid: error_groups(:system_primary_group).uuid)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        filter_bar = document.at_css(".inbox-workbench > .inbox-workbench-filters .inbox-filter-bar")

        expect(document.at_css("[data-product-tour-group-value='project-errors']")).to be_present
        expect(document.css("[data-tg-group='project-errors']").map { |node| node["data-tg-title"] }).to eq([
          "Inbox filters",
          "Error groups",
          "Error detail"
        ])
        expect(document.css("[data-tg-group='project-errors']").map { |node| node["data-tg-title"] }).not_to include("Error command center", "Project navigation")
        expect(document.at_css(".project-command-actions nav[aria-label='Project sections']")).to be_present
        expect(document.at_css(".project-signals-menu")).to be_nil
        expect(document.at_css(".project-command-actions .projects-secondary-button")).to be_nil
        expect(document.at_css(".projects-overview-strip[aria-label='Project status']")).to be_nil
        expect(filter_bar).to be_present
        expect(document.at_css(".inbox-workbench > .inbox-workbench-sidebar")).to be_nil
        expect(filter_bar.at_css("form.inbox-filter-search input[name='q']")["placeholder"]).to eq("Search errors...")
        expect(filter_bar.css("#inbox_counts .inbox-filter-link").map(&:text).join(" ")).to include("Open", "Introduced today", "Resolved", "Ignored", "Archived", "All")

        table = document.at_css("turbo-frame#project_inbox table.inbox-table-compact[aria-label='Error groups']")
        expect(table).to be_present
        expect(table.at_css("thead")).to be_nil
        expect(table.css("td.col-num, td.col-trend, td.col-stage, td.col-severity")).to be_empty

        row = table.at_css("tr##{ActionView::RecordIdentifier.dom_id(error_groups(:system_primary_group))}")
        expect(row).to be_present

        primary_line = row.at_css(".error-row-primary")
        metadata = row.at_css(".error-meta-row")

        expect(primary_line.at_css(".error-title").text).to eq("Primary inbox error")
        expect(primary_line.at_css(".error-subtitle").text).to eq("RuntimeError")
        expect(metadata.at_css(".error-meta-chip[title='1 event']")).to be_present
        expect(metadata.at_css(".error-meta-trend")["title"]).to include("7 day trend")
        expect(metadata.at_css(".stage-tag-compact")["title"]).to eq("Stage: production")
        expect(metadata.at_css(".severity-compact.severity-error")["title"]).to eq("Severity: error")
        expect(metadata.at_css(".error-meta-time")["title"]).to include("First seen", "Last seen")
        expect(metadata.css(".inbox-info-icon").size).to be >= 3
      end

      it "filters the inbox by assignee while preserving server-rendered controls" do
        project = create(:project, user: users(:one), name: "Assigned Inbox")
        api_key = create(:api_key, project: project, user: users(:one))
        member = create(:user, name: "Project Member")
        create(:project_membership, project: project, user: member)

        mine = create(:error_group, :with_occurrence,
                      project: project,
                      api_key: api_key,
                      title: "Mine assigned error",
                      assignee: users(:one),
                      assigned_by: users(:one),
                      assigned_at: Time.current)
        create(:error_group, :with_occurrence,
               project: project,
               api_key: api_key,
               title: "Member assigned error",
               assignee: member,
               assigned_by: users(:one),
               assigned_at: Time.current)
        create(:error_group, :with_occurrence,
               project: project,
               api_key: api_key,
               title: "Unassigned error")

        get inbox_project_path(project, filter: "unresolved", assignee: "me", group_uuid: mine.uuid)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        rows_text = document.css("tr.inbox-row").map(&:text).join(" ")
        selected_option = document.at_css("select[name='assignee'] option[selected]")

        expect(rows_text).to include("Mine assigned error")
        expect(rows_text).not_to include("Member assigned error", "Unassigned error")
        expect(rows_text).to include(users(:one).name.presence || users(:one).email)
        expect(selected_option["value"]).to eq("me")
        expect(document.at_css("input[name='assignee'][value='me']")).to be_present
        expect(document.at_css("#inbox_counts .inbox-filter-link[aria-current='page']").text).to include("Open", "1")

        get inbox_project_path(project, filter: "unresolved", assignee: "unassigned")

        document = Nokogiri::HTML.parse(response.body)
        rows_text = document.css("tr.inbox-row").map(&:text).join(" ")

        expect(rows_text).to include("Unassigned error")
        expect(rows_text).not_to include("Mine assigned error", "Member assigned error")

        get inbox_project_path(project, filter: "unresolved", assignee: member.uuid)

        document = Nokogiri::HTML.parse(response.body)
        rows_text = document.css("tr.inbox-row").map(&:text).join(" ")

        expect(rows_text).to include("Member assigned error")
        expect(rows_text).not_to include("Mine assigned error", "Unassigned error")
      end

      it "limits the initial inbox list for high-volume projects" do
        project = create(:project, user: users(:one), name: "Large Inbox")
        ProjectInboxData::INBOX_LIMIT.next.times do |offset|
          create(:error_group,
                 project: project,
                 title: "Large inbox error #{offset}",
                 last_seen_at: offset.minutes.ago,
                 first_seen_at: offset.minutes.ago)
        end

        get inbox_project_path(project, filter: "unresolved")

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        expect(document.css("tr.inbox-row").size).to eq(ProjectInboxData::INBOX_LIMIT)
        expect(document.at_css(".inbox-pane-header").text).to include("#{ProjectInboxData::INBOX_LIMIT} shown", "newest first")
      end

      it "ignores a selected event when it does not belong to the selected group" do
        project = create(:project, user: users(:one), integration_kind: "python", name: "Python Inbox")
        api_key = create(:api_key, user: users(:one), project: project, name: "python-inbox")

        selected_group_event = create(:ingest_event,
                                      project: project,
                                      api_key: api_key,
                                      event_type: :error,
                                      message: "Grouped event detail",
                                      fingerprint: "selected-group-error")
        selected_group = ErrorGroup.create!(
          project: project,
          latest_event: selected_group_event,
          fingerprint: "selected-group-error",
          title: "Grouped event detail",
          status: :unresolved,
          first_seen_at: selected_group_event.occurred_at,
          last_seen_at: selected_group_event.occurred_at,
          occurrence_count: 1
        )
        selected_group_event.update!(error_group: selected_group)
        ErrorOccurrence.create!(error_group: selected_group, ingest_event: selected_group_event, occurred_at: selected_group_event.occurred_at)

        mismatched_event = create(:ingest_event,
                                  project: project,
                                  api_key: api_key,
                                  event_type: :error,
                                  message: "Wrong event detail",
                                  fingerprint: "other-group-error")
        other_group = ErrorGroup.create!(
          project: project,
          latest_event: mismatched_event,
          fingerprint: "other-group-error",
          title: "Wrong event detail",
          status: :unresolved,
          first_seen_at: mismatched_event.occurred_at,
          last_seen_at: mismatched_event.occurred_at,
          occurrence_count: 1
        )
        mismatched_event.update!(error_group: other_group)
        ErrorOccurrence.create!(error_group: other_group, ingest_event: mismatched_event, occurred_at: mismatched_event.occurred_at)

        get inbox_project_path(project, group_uuid: selected_group.uuid, event_uuid: mismatched_event.uuid)

        expect(response).to have_http_status(:success)
        detail_frame = Nokogiri::HTML.parse(response.body).at_css('turbo-frame#error_detail')

        expect(detail_frame).to be_present
        expect(detail_frame.text).to include("Grouped event detail")
        expect(detail_frame.text).not_to include("Wrong event detail")
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "can view shared project" do
        get project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
      end
    end
  end

  describe "GET /projects/:uuid/settings" do
    it "requires authentication" do
      get settings_project_path(projects(:one))
      expect(response).to redirect_to(new_user_session_path)
    end

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
        expect(response.body).to include("https://docs.logister.org/integrations/javascript/")
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
        expect(response.body).to include("https://docs.logister.org/integrations/python/")
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
        expect(response.body).to include("https://docs.logister.org/integrations/dotnet/")
      end

      it "returns 404 for project user cannot access" do
        get settings_project_path(projects(:two), section: "admin")
        expect(response).to have_http_status(:not_found)
      end

      it "allows app admins to view settings for projects they do not own" do
        original = ENV["LOGISTER_ADMIN_EMAILS"]
        ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email

        get settings_project_path(projects(:two), section: "admin")

        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:two).name)
        expect(response.body).to include("Public API rate limits")
        expect(response.body).to include(project_rate_limit_path(projects(:two)))
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
        expect(response.body).to include("https://docs.logister.org/integrations/cfml/")
        expect(response.body).to include('target="_blank"')
      end
    end
  end

  describe "GET /projects/:uuid/performance" do
    it "requires authentication" do
      get performance_project_path(projects(:one))
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "returns success and shows performance page" do
        project = projects(:one)

        get performance_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include(project.name)
        expect(response.body).to include("Instrumentation help")
        expect(response.body).to include("Ruby integration docs")
        expect(response.body).to include("https://docs.logister.org/integrations/ruby/")

        document = Nokogiri::HTML.parse(response.body)
        expect(document.at_css("turbo-frame#performance_request_breakdown")["src"]).to eq(performance_request_breakdown_project_path(project))
        expect(document.at_css("turbo-frame#performance_database_load")["src"]).to eq(performance_database_load_project_path(project))
        expect(document.at_css("turbo-frame#performance_release_health")["src"]).to eq(performance_release_health_project_path(project))
        expect(document.at_css("turbo-frame#performance_transactions")["src"]).to eq(performance_transactions_project_path(project))
      end

      it "keeps insights top-level and tucks performance into the secondary project menu" do
        project = projects(:one)

        get performance_project_path(project)

        document = Nokogiri::HTML.parse(response.body)
        nav = document.at_css("nav[aria-label='Project sections']")
        links = nav.css("> a")
        secondary_menu = nav.at_css(".project-nav-menu")
        secondary_links = secondary_menu.css("a")
        active_link = nav.at_css("a[aria-current='page']")

        expect(links.map { |link| link["href"] }).to include(insights_project_path(project))
        expect(links.map { |link| link["href"] }).not_to include(performance_project_path(project))
        expect(links.map { |link| link.text.strip }).to include("Insights")
        expect(links.map { |link| link.text.strip }).not_to include("Performance")
        expect(secondary_menu["open"]).not_to be_nil
        expect(secondary_links.map { |link| link.text.strip }).to eq(%w[Events Performance Monitors])
        expect(secondary_links.map { |link| link["href"] }).to include(performance_project_path(project))
        expect(nav.at_css(".project-nav-insights")).to be_nil
        expect(active_link["href"]).to eq(performance_project_path(project))
      end

      it "filters and cursor-paginates transaction events" do
        project = create(:project, user: users(:one), name: "Transaction Browser")
        api_key = create(:api_key, project: project, user: users(:one))
        create(:ingest_event,
               :transaction,
               project: project,
               api_key: api_key,
               level: "error",
               message: "checkout newest transaction",
               occurred_at: 1.minute.ago,
               context: { "transaction_name" => "POST /checkout", "duration_ms" => 650, "status" => 503 })
        create(:ingest_event,
               :transaction,
               project: project,
               api_key: api_key,
               level: "error",
               message: "checkout older transaction",
               occurred_at: 10.minutes.ago,
               context: { "transaction_name" => "POST /checkout", "duration_ms" => 700, "status" => 500 })
        create(:ingest_event,
               :transaction,
               project: project,
               api_key: api_key,
               message: "healthcheck transaction",
               occurred_at: 2.minutes.ago,
               context: { "transaction_name" => "GET /health", "duration_ms" => 25, "status" => 200 })
        create(:ingest_event,
               project: project,
               api_key: api_key,
               event_type: :error,
               level: "error",
               message: "Checkout failed",
               occurred_at: 30.seconds.ago,
               context: { "transaction_name" => "POST /checkout" })

        get performance_transactions_project_path(project, period: "all", status: "errored", min_duration_ms: "500", q: "checkout", per_page: 1)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        table = document.at_css("table[aria-label='Transaction events']")
        rows = table.css("tbody tr")
        older_link = document.css("nav[aria-label='Pagination'] a").find { |link| link.text.strip == "Older" }

        expect(rows.size).to eq(1)
        expect(rows.first.text).to include("POST /checkout", "650.0 ms", "503 error", "1", "View event", "Open error")
        expect(rows.first.text).not_to include("GET /health")
        expect(older_link).to be_present
        expect(older_link["href"]).to include("before=", "status=errored", "q=checkout")

        get older_link["href"]

        document = Nokogiri::HTML.parse(response.body)
        rows = document.css("table[aria-label='Transaction events'] tbody tr")

        expect(rows.size).to eq(1)
        expect(rows.first.text).to include("POST /checkout", "700.0 ms", "500 error")
        expect(document.css("nav[aria-label='Pagination'] a").map { |link| link.text.strip }).to include("Newer")
      end

      it "shows JavaScript integration docs on JavaScript performance pages" do
        project = create(:project, user: users(:one), integration_kind: "javascript", name: "Node Perf")

        get performance_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("JavaScript integration docs")
        expect(response.body).to include("https://docs.logister.org/integrations/javascript/")
      end

      it "renders database load stats when db.query metrics exist" do
        IngestEvent.create!(
          project: projects(:one),
          api_key: api_keys(:one),
          event_type: :metric,
          level: "info",
          message: "db.query",
          fingerprint: "db-query-fresh",
          context: {
            duration_ms: 42.75,
            name: "User Load",
            sql: "SELECT \"users\".* FROM \"users\" WHERE \"users\".\"id\" = 1"
          },
          occurred_at: Time.current
        )
        get performance_database_load_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Database load (24h)")
        expect(response.body).to include("1 queries captured")
        expect(response.body).to include("42.75 ms")
      end

      it "returns 404 for project user cannot access" do
        get performance_project_path(projects(:two))
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns success and shows performance page" do
        get performance_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
      end
    end
  end

  describe "GET /projects/:uuid/monitors" do
    it "requires authentication" do
      get monitors_project_path(projects(:one))
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "returns success and shows monitors page" do
        get monitors_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Cron and uptime monitors")
        expect(response.body).to include("Ruby integration docs")
        expect(response.body).to include("https://docs.logister.org/integrations/ruby/")
      end

      it "shows primary project paths directly and secondary paths in a menu" do
        project = projects(:one)

        get monitors_project_path(project)

        document = Nokogiri::HTML.parse(response.body)
        nav = document.at_css("nav[aria-label='Project sections']")
        links = nav.css("> a")
        secondary_menu = nav.at_css(".project-nav-menu")
        secondary_links = secondary_menu.css("a")
        active_link = nav.at_css("a[aria-current='page']")

        expect(links.map { |link| link.text.strip }).to eq(%w[Home Inbox Insights Deployments Setup Settings])
        expect(links.map { |link| link["href"] }).to include(
          project_path(project),
          inbox_project_path(project),
          insights_project_path(project),
          deployments_project_path(project),
          setup_project_path(project),
          settings_project_path(project)
        )
        expect(links.map { |link| link["href"] }).not_to include(
          activity_project_path(project),
          performance_project_path(project),
          monitors_project_path(project)
        )
        expect(secondary_menu["open"]).not_to be_nil
        expect(secondary_links.map { |link| link.text.strip }).to eq(%w[Events Performance Monitors])
        expect(secondary_links.map { |link| link["href"] }).to include(
          activity_project_path(project),
          performance_project_path(project),
          monitors_project_path(project)
        )
        expect(nav.at_css(".project-nav-activity")).to be_nil
        expect(active_link["href"]).to eq(monitors_project_path(project))
      end

      it "shows JavaScript integration docs on JavaScript monitor pages" do
        project = create(:project, user: users(:one), integration_kind: "javascript", name: "Node Monitor")

        get monitors_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("JavaScript integration docs")
        expect(response.body).to include("https://docs.logister.org/integrations/javascript/")
      end

      it "shows Python integration docs on Python monitor pages" do
        project = create(:project, user: users(:one), integration_kind: "python", name: "Python Monitor")

        get monitors_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Python integration docs")
        expect(response.body).to include("https://docs.logister.org/integrations/python/")
      end

      it "returns 404 for project user cannot access" do
        get monitors_project_path(projects(:two))
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns success and shows monitors page" do
        get monitors_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Cron and uptime monitors")
      end
    end
  end

  describe "GET /projects/:uuid/activity" do
    it "requires authentication" do
      get activity_project_path(projects(:one))
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "returns success and shows activity page" do
        get activity_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Events")
        expect(response.body).to include("Ruby integration docs")
        expect(response.body).to include("https://docs.logister.org/integrations/ruby/")
      end

      it "filters and cursor-paginates custom events" do
        project = create(:project, user: users(:one), name: "Activity Browser")
        api_key = create(:api_key, project: project, user: users(:one))
        create(:ingest_event,
               :log,
               project: project,
               api_key: api_key,
               message: "paged log newest",
               occurred_at: 1.minute.ago)
        create(:ingest_event,
               :log,
               project: project,
               api_key: api_key,
               message: "paged log older",
               occurred_at: 10.minutes.ago)
        create(:ingest_event,
               :transaction,
               project: project,
               api_key: api_key,
               message: "paged transaction hidden",
               occurred_at: 2.minutes.ago)

        get activity_project_path(project, event_type: "log", q: "paged", per_page: 1)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        rows = document.css("table[aria-label='Events'] tbody tr")
        older_link = document.css("nav[aria-label='Pagination'] a").find { |link| link.text.strip == "Older" }

        expect(rows.size).to eq(1)
        expect(rows.first.text).to include("paged log newest")
        expect(rows.first.text).not_to include("paged log older", "paged transaction hidden")
        expect(older_link).to be_present
        expect(older_link["href"]).to include("before=", "event_type=log", "q=paged")

        get older_link["href"]

        document = Nokogiri::HTML.parse(response.body)
        rows = document.css("table[aria-label='Events'] tbody tr")

        expect(rows.size).to eq(1)
        expect(rows.first.text).to include("paged log older")
        expect(document.css("nav[aria-label='Pagination'] a").map { |link| link.text.strip }).to include("Newer")
      end

      it "shows JavaScript-specific empty-state guidance for JavaScript projects" do
        project = create(:project, user: users(:one), integration_kind: "javascript", name: "Node Activity")

        get activity_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("No events yet")
        expect(response.body).to include("logister-js")
        expect(response.body).to include("send one Node, Express, or worker event")
        expect(response.body).to include("https://docs.logister.org/integrations/javascript/")
      end

      it "shows JavaScript logger metadata inline for JavaScript log events" do
        project = create(:project, user: users(:one), integration_kind: "javascript", name: "Node Activity")
        api_key = create(:api_key, user: users(:one), project: project, name: "javascript-activity")
        IngestEvent.create!(
          project: project,
          api_key: api_key,
          event_type: :log,
          level: "warning",
          message: "Queue backlog rising",
          context: {
            logger_name: "console",
            logger: {
              method: "warn",
              filename: "worker.js",
              function: "flushQueue"
            },
            route: "/jobs/email-drain"
          },
          occurred_at: Time.current
        )

        get activity_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Queue backlog rising")
        expect(response.body).to include("console")
        expect(response.body).to include("warn")
        expect(response.body).to include("flushQueue() in worker.js")
        expect(response.body).to include("/jobs/email-drain")
      end

      it "shows Python-specific empty-state guidance for Python projects" do
        project = create(:project, user: users(:one), integration_kind: "python", name: "Python Activity")

        get activity_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("No events yet")
        expect(response.body).to include("logister-python")
        expect(response.body).to include("send one web or worker event")
        expect(response.body).to include("https://docs.logister.org/integrations/python/")
      end

      it "shows .NET-specific empty-state guidance for .NET projects" do
        project = create(:project, user: users(:one), integration_kind: "dotnet", name: "Dotnet Activity")

        get activity_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("No events yet")
        expect(response.body).to include("Logister.AspNetCore")
        expect(response.body).to include("send one request or worker event")
        expect(response.body).to include("https://docs.logister.org/integrations/dotnet/")
      end

      it "shows .NET logger metadata inline for .NET log events" do
        project = create(:project, user: users(:one), integration_kind: "dotnet", name: "Dotnet Activity")
        api_key = create(:api_key, user: users(:one), project: project, name: "dotnet-activity")
        IngestEvent.create!(
          project: project,
          api_key: api_key,
          event_type: :log,
          level: "warning",
          message: "Approval queue backlog rising",
          context: {
            logger_name: "QuriaTime.Web.Services.ApprovalService",
            logger: {
              event_name: "ApprovalQueueBacklog"
            },
            route: "BackgroundService NotificationOutboxWorker",
            status: 200,
            framework: "aspnetcore"
          },
          occurred_at: Time.current
        )

        get activity_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Approval queue backlog rising")
        expect(response.body).to include("QuriaTime.Web.Services.ApprovalService")
        expect(response.body).to include("ApprovalQueueBacklog")
        expect(response.body).to include("BackgroundService NotificationOutboxWorker")
        expect(response.body).to include("status 200")
      end

      it "shows Python logger metadata inline for Python log events" do
        project = create(:project, user: users(:one), integration_kind: "python", name: "Python Activity")
        api_key = create(:api_key, user: users(:one), project: project, name: "python-activity")
        IngestEvent.create!(
          project: project,
          api_key: api_key,
          event_type: :log,
          level: "warning",
          message: "Inventory cache miss",
          context: {
            logger_name: "inventory.cache",
            logger: {
              filename: "worker.py",
              function: "refresh_cache"
            },
            task_name: "inventory.refresh"
          },
          occurred_at: Time.current
        )

        get activity_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Inventory cache miss")
        expect(response.body).to include("inventory.cache")
        expect(response.body).to include("refresh_cache() in worker.py")
        expect(response.body).to include("task inventory.refresh")
      end

      it "returns 404 for project user cannot access" do
        get activity_project_path(projects(:two))
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns success and shows activity page" do
        get activity_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Events")
      end

      it "shows CFML integration docs on CFML activity pages" do
        get activity_project_path(projects(:two))
        expect(response).to have_http_status(:success)
        expect(response.body).to include("CFML integration docs")
        expect(response.body).to include("https://docs.logister.org/integrations/cfml/")
      end
    end
  end

  describe "GET /projects/:uuid/edit" do
    it "requires authentication" do
      get edit_project_path(projects(:one))
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "returns success and shows edit form" do
        get edit_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Edit project")
        document = Nokogiri::HTML.parse(response.body)

        expect(document.at_css("input[name='project[slug]']")).to be_nil
        expect(document.at_css("select[name='project[integration_kind]']")).to be_nil
        expect(document.at_css("input[name='project[integration_kind]']")).to be_nil
        expect(document.css(".integration-choice-panel")).to be_empty
        expect(response.body).to include("Project type is locked after creation")
        expect(response.body).to include(projects(:one).integration_label)
      end

      it "returns 404 for project user cannot access" do
        get edit_project_path(projects(:two))
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns 404 (only owner can edit)" do
        get edit_project_path(projects(:one))
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /projects/:uuid" do
    it "requires authentication" do
      patch project_path(projects(:one)), params: { project: { name: "Updated" } }
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "updates project and redirects to settings" do
        project = projects(:one)
        original_slug = project.slug

        patch project_path(project), params: { project: { name: "Renamed App", slug: "manual-change", description: "New desc", integration_kind: "http_api" } }

        expect(response).to redirect_to(settings_project_path(project, section: "general"))
        expect(project.reload.name).to eq("Renamed App")
        expect(project.slug).to eq(original_slug)
        expect(project.description).to eq("New desc")
        expect(project.integration_kind).to eq("ruby")
      end

      it "returns 404 for project user cannot access" do
        patch project_path(projects(:two)), params: { project: { name: "Nope" } }
        expect(response).to have_http_status(:not_found)
      end

      it "renders edit with errors when invalid" do
        patch project_path(projects(:one)), params: { project: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Edit project")
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns 404 (only owner can update)" do
        patch project_path(projects(:one)), params: { project: { name: "Nope" } }
        expect(response).to have_http_status(:not_found)
        expect(projects(:one).reload.name).not_to eq("Nope")
      end
    end
  end

  describe "POST /projects" do
    before { sign_in users(:one) }

    let(:retention_policy_attributes) do
      {
        hot_retention_days: "60",
        trace_retention_days: "90",
        error_retention_days: "180",
        archive_enabled: "1",
        archive_before_delete: "1"
      }
    end

    it "does not render slug as a user-editable field" do
      get new_project_path

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML.parse(response.body)

      expect(document.at_css("input[name='project[slug]']")).to be_nil
      expect(document.at_css("select[name='project[integration_kind]']")).to be_nil
      expect(document.css(".integration-choice-title").map(&:text)).to eq([
        "Manual / HTTP API",
        "Cloudflare Pages",
        "Android app",
        "iOS app",
        "Ruby gem",
        ".NET / ASP.NET Core",
        "JavaScript / TypeScript",
        "Python",
        "CFML"
      ])
      expect(document.css(".integration-choice-panel").map(&:text).join(" ")).to include(
        "Ruby gem",
        ".NET / ASP.NET Core",
        "CFML",
        "JavaScript / TypeScript",
        "Python",
        "Cloudflare Pages",
        "Android app",
        "iOS app",
        "Manual / HTTP API"
      )
      expect(document.css("[data-tg-group='project-new']").map { |node| node["data-tg-title"] }).to eq([
        "Name the app",
        "Choose integration type",
        "Choose retention policy"
      ])
      expect(document.css("[data-tg-group='project-new']").map { |node| node["data-tg-tour"] }.join(" ")).to include(
        "Enter a clear name",
        "runtime or manual HTTP path",
        "first event",
        "whether cleanup must archive first"
      )
      expect(document.at_css("input[name='project[integration_kind]'][type='radio'][checked]")["value"]).to eq("ruby")
      expect(document.at_css("select[name='project[retention_policy_attributes][hot_retention_days]']")).to be_present
      expect(document.at_css("select[name='project[retention_policy_attributes][trace_retention_days]']")).to be_present
      expect(document.at_css("select[name='project[retention_policy_attributes][error_retention_days]']")).to be_present
      expect(document.at_css("input[name='project[retention_policy_attributes][archive_enabled]'][type='checkbox']")).to be_present
      expect(document.at_css("input[name='project[retention_policy_attributes][archive_before_delete]'][type='checkbox']")).to be_present
      expect(response.body.index('name="project[description]"')).to be < response.body.index("integration-picker")
      expect(response.body.index("integration-picker")).to be < response.body.index("Data retention")
    end

    it "creates project with the selected retention policy and redirects" do
      expect {
        post projects_path, params: {
          project: {
            name: "New App",
            slug: "manual-change",
            description: "Desc",
            integration_kind: "http_api",
            retention_policy_attributes: retention_policy_attributes
          }
        }
      }.to change(Project, :count).by(1)
        .and change(ProjectRetentionPolicy, :count).by(1)

      project = Project.last
      expect(response).to redirect_to(setup_project_path(project))
      expect(project.slug).to eq("new-app")
      expect(project.integration_kind).to eq("http_api")
      expect(project.retention_policy).to have_attributes(
        hot_retention_days: 60,
        trace_retention_days: 90,
        error_retention_days: 180,
        archive_enabled: true,
        archive_before_delete: true
      )
      follow_redirect!
      expect(response.body).to include("Project created")
      expect(response.body).to include("Connect this project", "First event guide")
      expect(response.body).to include("Send one representative event")
      expect(response.body).to include("Manual / HTTP API")
      expect(response.body).to include("HTTP API docs")
    end

    it "does not create an active project when retention settings are omitted" do
      expect {
        post projects_path, params: {
          project: {
            name: "New App",
            description: "Desc",
            integration_kind: "http_api"
          }
        }
      }.not_to change(Project, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Choose a data retention policy before creating the project.")
    end

    it "renders new with retention validation errors" do
      expect {
        post projects_path, params: {
          project: {
            name: "New App",
            integration_kind: "ruby",
            retention_policy_attributes: retention_policy_attributes.merge(
              archive_enabled: "0",
              archive_before_delete: "1"
            )
          }
        }
      }.not_to change(Project, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Data retention")
      expect(response.body).to include("requires retention exports to be enabled")
    end

    it "renders new with errors when invalid" do
      post projects_path, params: {
        project: {
          name: "",
          retention_policy_attributes: retention_policy_attributes
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /projects/:uuid" do
    context "when owner" do
      before { sign_in users(:one) }

      it "deletes project and redirects" do
        project = projects(:one)
        expect {
          delete project_path(project)
        }.to change(Project, :count).by(-1)
        expect(response).to redirect_to(projects_path)
      end
    end

    context "when shared member" do
      before { sign_in users(:two) }

      it "returns 404 and does not delete" do
        expect {
          delete project_path(projects(:one))
        }.not_to change(Project, :count)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /projects/:uuid/archive" do
    context "when owner" do
      before { sign_in users(:one) }

      it "archives the project and redirects to active projects" do
        project = projects(:one)
        api_key = api_keys(:one)

        patch archive_project_path(project)

        expect(response).to redirect_to(projects_path)
        expect(project.reload).to be_archived
        expect(api_key.reload.revoked_at).to be_present
      end
    end

    context "when shared member" do
      before { sign_in users(:two) }

      it "returns 404 and does not archive" do
        project = projects(:one)

        patch archive_project_path(project)

        expect(response).to have_http_status(:not_found)
        expect(project.reload).not_to be_archived
      end
    end
  end

  describe "PATCH /projects/:uuid/restore" do
    context "when owner" do
      before { sign_in users(:one) }

      it "restores an archived project" do
        project = create(:project, :archived, user: users(:one))

        patch restore_project_path(project)

        expect(response).to redirect_to(project_path(project))
        expect(project.reload).not_to be_archived
      end
    end
  end
end

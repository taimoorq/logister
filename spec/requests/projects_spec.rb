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
        expect(response.body).to include(">Docs<")
        expect(response.body).to include("documentation section")
        expect(response.body).to include("https://docs.logister.org/")
        expect(response.body).to include('target="_blank"')
        expect(response.body).to include('rel="noopener noreferrer"')
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

        get project_path(project, group_uuid: error_group.uuid)

        expect(response).to have_http_status(:success)
        detail_frame = Nokogiri::HTML.parse(response.body).at_css('turbo-frame#error_detail')

        expect(detail_frame).to be_present
        expect(detail_frame.text).to include("Latest grouped error")
        expect(detail_frame.text).to include("Related logs")
      end

      it "marks the active filter and selected inbox row with accessible state attributes" do
        get project_path(projects(:system_inbox), filter: "unresolved", group_uuid: error_groups(:system_primary_group).uuid)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        active_filter = document.at_css(".inbox-filter-link[aria-current='page']")
        selected_row = document.at_css("tr.inbox-row[aria-selected='true']")

        expect(active_filter).to be_present
        expect(active_filter.text).to include("Open")
        expect(selected_row).to be_present
        expect(selected_row["id"]).to eq(ActionView::RecordIdentifier.dom_id(error_groups(:system_primary_group)))
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

        get project_path(project, group_uuid: selected_group.uuid, event_uuid: mismatched_event.uuid)

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

      it "returns success and shows settings (API keys, project access)" do
        get settings_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("API keys")
        expect(response.body).to include("Project access")
        expect(response.body).to include("Integration guide")
        expect(response.body).to include("Ruby gem")
        expect(response.body).to include("logister-ruby")
        expect(response.body).to include("https://docs.logister.org/integrations/ruby/")
        expect(response.body).to include('target="_blank"')
      end

      it "shows JavaScript-specific integration guidance for logister-js projects" do
        project = create(:project, user: users(:one), integration_kind: "javascript", name: "Node App")

        get settings_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("JavaScript / TypeScript")
        expect(response.body).to include("logister-js")
        expect(response.body).to include("logister-js/express")
        expect(response.body).to include("instrumentConsole")
        expect(response.body).to include("source maps")
        expect(response.body).to include("LOGISTER_RELEASE")
        expect(response.body).to include("https://docs.logister.org/integrations/javascript/")
      end

      it "shows Python-specific integration guidance for logister-python projects" do
        project = create(:project, user: users(:one), integration_kind: "python", name: "Python App")

        get settings_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Python")
        expect(response.body).to include("logister-python")
        expect(response.body).to include("instrument_fastapi")
        expect(response.body).to include("instrument_flask")
        expect(response.body).to include("https://docs.logister.org/integrations/python/")
      end

      it "shows .NET-specific integration guidance for logister-dotnet projects" do
        project = create(:project, user: users(:one), integration_kind: "dotnet", name: "QuriaTime")

        get settings_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include(".NET / ASP.NET Core")
        expect(response.body).to include("Logister.AspNetCore")
        expect(response.body).to include("AddLogister")
        expect(response.body).to include("UseLogisterExceptionReporting")
        expect(response.body).to include("CaptureMetricAsync")
        expect(response.body).to include("https://docs.logister.org/integrations/dotnet/")
      end

      it "returns 404 for project user cannot access" do
        get settings_project_path(projects(:two))
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns success and shows project (read-only settings)" do
        get settings_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
      end

      it "shows CFML-specific integration guidance for CFML projects" do
        get settings_project_path(projects(:two))
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
        get performance_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Instrumentation help")
        expect(response.body).to include("Ruby integration docs")
        expect(response.body).to include("https://docs.logister.org/integrations/ruby/")
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
        get performance_project_path(projects(:one))
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
        expect(response.body).to include("Custom events")
        expect(response.body).to include("Ruby integration docs")
        expect(response.body).to include("https://docs.logister.org/integrations/ruby/")
      end

      it "shows JavaScript-specific empty-state guidance for JavaScript projects" do
        project = create(:project, user: users(:one), integration_kind: "javascript", name: "Node Activity")

        get activity_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("client.captureMetric()")
        expect(response.body).to include("client.checkIn()")
        expect(response.body).to include("instrumentConsole()")
        expect(response.body).to include("browser")
        expect(response.body).to include("route")
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
        expect(response.body).to include("client.capture_metric()")
        expect(response.body).to include("client.check_in()")
        expect(response.body).to include("instrument_flask()")
        expect(response.body).to include("https://docs.logister.org/integrations/python/")
      end

      it "shows .NET-specific empty-state guidance for .NET projects" do
        project = create(:project, user: users(:one), integration_kind: "dotnet", name: "Dotnet Activity")

        get activity_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("CaptureMetricAsync()")
        expect(response.body).to include("CheckInAsync()")
        expect(response.body).to include("UseLogisterExceptionReporting()")
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
        expect(response.body).to include("Custom events")
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
        patch project_path(project), params: { project: { name: "Renamed App", description: "New desc", integration_kind: "cfml" } }
        expect(response).to redirect_to(settings_project_path(project))
        expect(project.reload.name).to eq("Renamed App")
        expect(project.description).to eq("New desc")
        expect(project.integration_kind).to eq("cfml")
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

    it "creates project and redirects" do
      expect {
        post projects_path, params: { project: { name: "New App", description: "Desc", integration_kind: "cfml" } }
      }.to change(Project, :count).by(1)
      expect(response).to redirect_to(project_path(Project.last))
      expect(Project.last.integration_kind).to eq("cfml")
      follow_redirect!
      expect(response.body).to include("Project created")
    end

    it "renders new with errors when invalid" do
      post projects_path, params: { project: { name: "" } }
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
end

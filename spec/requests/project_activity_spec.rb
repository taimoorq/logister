# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Project activity", type: :request do
  describe "GET /projects/:uuid/activity" do
    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "returns success and shows activity page" do
        get activity_project_path(projects(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Events")
        expect(response.body).to include("Ruby integration docs")
        expect(response.body).to include("https://logister.org/docs/integrations/ruby/")
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

      it "uses receipt discovery and typed evidence filters for mobile app activity" do
        project = create(:project, :ios, user: users(:one), name: "iOS Activity")
        api_key = create(:api_key, project: project, user: users(:one))
        received_at = 5.minutes.ago.change(usec: 0)
        activity = create(
          :ingest_event,
          :log,
          project: project,
          api_key: api_key,
          message: "Checkout cache refreshed",
          occurred_at: 5.days.ago,
          created_at: received_at,
          context: {
            "platform" => "ios",
            "apple_platform" => "ios",
            "release" => "com.acme.shop@4.2.0+310",
            "diagnostic" => { "source" => "sdk" },
            "app" => { "identifier" => "com.acme.shop", "version_name" => "4.2.0", "version_code" => "310", "process" => "AcmeShop", "screen" => "Checkout" },
            "distribution" => { "channel" => "testflight" },
            "session" => { "id" => "session-private-value" },
            "trace_id" => "trace-private-value",
            "telemetry_evidence" => {
              "schema_version" => 1,
              "source" => "sdk",
              "kind" => "log",
              "time" => {
                "precision" => "exact",
                "occurred_at" => 5.days.ago.utc.iso8601,
                "received_at" => received_at.utc.iso8601
              }
            }
          }
        )
        hidden = create(
          :ingest_event,
          :log,
          project: project,
          api_key: api_key,
          message: "Different activity source",
          context: {
            "platform" => "ios",
            "apple_platform" => "ios",
            "diagnostic" => { "source" => "metrickit" },
            "app" => { "version_code" => "311" },
            "distribution" => { "channel" => "app_store" },
            "telemetry_evidence" => { "schema_version" => 1, "source" => "metrickit", "time" => { "precision" => "received_only", "received_at" => Time.current.utc.iso8601 } }
          }
        )
        error_event = create(
          :ingest_event,
          project: project,
          api_key: api_key,
          message: "Related checkout error",
          occurred_at: activity.occurred_at + 1.minute,
          context: { "platform" => "ios", "trace_id" => "trace-private-value", "exception" => { "type" => "CheckoutError" } }
        )
        ErrorGroupingService.call(error_event)

        get activity_project_path(
          project,
          source: "sdk",
          time_precision: "exact",
          build_number: "310",
          channel: "testflight",
          platform: "ios"
        )

        expect(response).to have_http_status(:success)
        document = Nokogiri::HTML.parse(response.body)
        rows = document.css("table[aria-label='Events'] tbody tr")
        expect(rows.size).to eq(1)
        expect(rows.first.text).to include(
          "Checkout cache refreshed",
          "Exact occurrence",
          "Logister SDK",
          "4.2.0 (310) · testflight",
          "AcmeShop · Checkout",
          "Related issue:"
        )
        expect(document.text).to include("App activity", "Receipt period", "Stability")
        expect(response.body).to include("Open same scope in Insights", "attributes%5Bbuild_number%5D=310", "attributes%5Bevidence_source%5D=sdk")
        expect(document.text).not_to include(hidden.message, "session-private-value", "trace-private-value")
      end

      it "distinguishes an empty receipt window from a project with no mobile activity" do
        project = create(:project, :android, user: users(:one), name: "Android Activity")
        create(
          :ingest_event,
          :log,
          project: project,
          api_key: create(:api_key, project: project, user: users(:one)),
          occurred_at: 3.days.ago,
          created_at: 3.days.ago,
          context: { "platform" => "android" }
        )

        get activity_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("No app activity was received in this window")
        expect(response.body).not_to include("No events yet")
      end

      {
        "javascript" => [ "JavaScript", "logister-js", "send one Node, Express, or worker event" ],
        "python" => [ "Python", "logister-python", "send one web or worker event" ],
        "dotnet" => [ ".NET", "Logister.AspNetCore", "send one request or worker event" ]
      }.each do |kind, (label, package, prompt)|
        it "shows #{label}-specific empty-state guidance for #{label} projects" do
          project = create(:project, user: users(:one), integration_kind: kind)

          get activity_project_path(project)

          expect(response).to have_http_status(:success)
          expect(response.body).to include("No events yet", package, prompt, "https://logister.org/docs/integrations/#{kind}/")
        end
      end

      it "shows JavaScript logger metadata inline for JavaScript log events" do
        project = create(:project, user: users(:one), integration_kind: "javascript", name: "Node Activity")
        api_key = create(:api_key, user: users(:one), project: project, name: "javascript-activity")
        IngestEvent.create!(
          project: project,
          api_key_id: api_key.id,
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

      it "shows .NET logger metadata inline for .NET log events" do
        project = create(:project, user: users(:one), integration_kind: "dotnet", name: "Dotnet Activity")
        api_key = create(:api_key, user: users(:one), project: project, name: "dotnet-activity")
        IngestEvent.create!(
          project: project,
          api_key_id: api_key.id,
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
          api_key_id: api_key.id,
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
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "shows CFML integration docs on CFML activity pages" do
        get activity_project_path(projects(:two))
        expect(response).to have_http_status(:success)
        expect(response.body).to include("CFML integration docs")
        expect(response.body).to include("https://logister.org/docs/integrations/cfml/")
      end
    end
  end
end

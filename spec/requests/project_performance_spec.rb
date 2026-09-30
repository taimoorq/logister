# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Project performance", type: :request do
  describe "GET /projects/:uuid/performance" do
    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "returns success and shows performance page" do
        project = projects(:one)

        get performance_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include(project.name)
        expect(response.body).to include("Instrumentation help")
        expect(response.body).to include("Ruby integration docs")
        expect(response.body).to include("https://logister.org/docs/integrations/ruby/")

        document = Nokogiri::HTML.parse(response.body)
        expect(document.at_css("turbo-frame#performance_request_breakdown")["src"]).to eq(performance_request_breakdown_project_path(project))
        expect(document.at_css("turbo-frame#performance_database_load")["src"]).to eq(performance_database_load_project_path(project))
        expect(document.at_css("turbo-frame#performance_release_health")).to be_nil
        expect(document.at_css("turbo-frame#release_health")).to be_nil
        expect(document.at_css("turbo-frame#performance_transactions")["src"]).to eq(performance_transactions_project_path(project))
      end

      it "shows one tab per section and no overflow menu on Performance" do
        project = create(:project, user: users(:one))

        get performance_project_path(project)

        document = Nokogiri::HTML.parse(response.body)
        nav = document.at_css("nav[aria-label='Project sections']")
        links = nav.css("> a")
        active_link = nav.at_css("a[aria-current='page']")

        expect(links.map { |link| link.text.strip }).to eq(%w[Overview Issues Performance Releases Explore Settings])
        expect(links.map { |link| link["href"] }).to eq([
          project_path(project),
          inbox_project_path(project),
          performance_project_path(project),
          deployments_project_path(project),
          activity_project_path(project),
          settings_project_path(project)
        ])
        expect(document.at_css(".project-nav-menu")).to be_nil
        expect(document.at_css("nav[aria-label='Explore views']")).to be_nil
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

        get performance_transactions_project_path(project, period: "all", status: "errored", min_duration_ms: "500", q: "checkout", per_page: 1),
            headers: { "Turbo-Frame" => "performance_transactions" }

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

        get older_link["href"], headers: { "Turbo-Frame" => "performance_transactions" }

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
        expect(response.body).to include("https://logister.org/docs/integrations/javascript/")
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
        get performance_database_load_project_path(projects(:one)),
            headers: { "Turbo-Frame" => "performance_database_load" }
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Database load (24h)")
        expect(response.body).to include("1 queries captured")
        expect(response.body).to include("42.75 ms")
      end

      it "redirects direct lazy-panel visits to Performance and rejects a mismatched frame" do
        project = projects(:one)

        get performance_database_load_project_path(project)

        expect(response).to redirect_to("#{performance_project_path(project)}#performance_database_load")

        get performance_database_load_project_path(project), headers: { "Turbo-Frame" => "performance_transactions" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to be_blank
      end
    end
  end
end

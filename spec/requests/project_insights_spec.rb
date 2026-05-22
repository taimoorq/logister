# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project insights", type: :request do
  describe "GET /projects/:uuid/insights" do
    it "requires authentication" do
      get insights_project_path(projects(:one))

      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in" do
      before { sign_in users(:one) }

      it "renders the isolated dashboard builder shell without blocking on aggregates" do
        project = create(:project, user: users(:one), name: "Insights App")
        api_key = create(:api_key, project: project, user: users(:one))
        create(:ingest_event, :metric, project: project, api_key: api_key, message: "queue.depth", occurred_at: 10.minutes.ago)

        expect(ProjectInsights).not_to receive(:catalog_for)
        expect(ProjectInsights).not_to receive(:filter_options)

        get insights_project_path(project)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("project-insights")
        expect(response.body).to include("view-transition-class: project-insights-panel")
        expect(response.body).to include("Overview")
        expect(response.body).to include("Add chart series")
        expect(response.body).to include("Attribute")
        expect(response.body).not_to include("Analysis workbook")
        expect(response.body).not_to include("Health readout")
        expect(response.body).not_to include("queue.depth")
        expect(response.body).to include(insights_data_project_path(project))
      end
    end
  end

  describe "GET /projects/:uuid/insights/data" do
    before { sign_in users(:one) }

    it "returns combined activity and performance series for selected metrics" do
      travel_to Time.zone.local(2026, 5, 21, 12, 0, 0) do
        project = create(:project, user: users(:one), name: "Chartable App")
        api_key = create(:api_key, project: project, user: users(:one))
        context = {
          "environment" => "production",
          "release" => "2026.05.21",
          "tenant_id" => "acme",
          "plan" => "pro"
        }
        beta_context = context.merge("tenant_id" => "beta", "plan" => "free")

        create(:ingest_event, project: project, api_key: api_key, message: "Checkout failed", context: context, occurred_at: 50.minutes.ago)
        create(:ingest_event, :log, project: project, api_key: api_key, message: "Checkout started", context: context, occurred_at: 45.minutes.ago)
        create(:ingest_event, :transaction, project: project, api_key: api_key, context: context.merge("duration_ms" => 100), occurred_at: 40.minutes.ago)
        create(:ingest_event, :transaction, project: project, api_key: api_key, context: context.merge("duration_ms" => 200), occurred_at: 35.minutes.ago)
        create(:ingest_event, :metric, project: project, api_key: api_key, message: "db.query", context: context.merge("duration_ms" => 50), occurred_at: 30.minutes.ago)
        create(:ingest_event, :metric, project: project, api_key: api_key, message: "queue.depth", context: context.merge("value" => 7), occurred_at: 25.minutes.ago)
        create(:ingest_event, :metric, project: project, api_key: api_key, message: "queue.depth", context: context.merge("value" => 9), occurred_at: 24.minutes.ago)
        create(:ingest_event, :log, project: project, api_key: api_key, message: "Other tenant", context: beta_context, occurred_at: 20.minutes.ago)

        get insights_data_project_path(project), params: {
          window: "1h",
          environment: "production",
          attributes: { tenant_id: "acme" },
          metrics: [ "events.total", "transactions.p95", "db.query.avg", "metric:queue.depth", "metric_value:queue.depth" ]
        }

        expect(response).to have_http_status(:success)

        json = JSON.parse(response.body)
        series_by_key = json.fetch("metric_series").index_by { |series| series.fetch("key") }

        expect(json.fetch("summary")).to include("events" => 7, "errors" => 1, "transactions" => 2, "metrics" => 3)
        expect(json.fetch("selected_metrics")).to include("events.total", "transactions.p95", "db.query.avg", "metric:queue.depth", "metric_value:queue.depth")
        expect(series_by_key.fetch("events.total").fetch("data").sum { |point| point.fetch("value") }).to eq(7)
        expect(series_by_key.fetch("transactions.p95").fetch("data").map { |point| point.fetch("value") }.max).to be > 0
        expect(series_by_key.fetch("db.query.avg").fetch("data").map { |point| point.fetch("value") }.max).to eq(50.0)
        expect(series_by_key.fetch("metric:queue.depth").fetch("data").sum { |point| point.fetch("value") }).to eq(2)
        expect(series_by_key.fetch("metric_value:queue.depth").fetch("data").map { |point| point.fetch("value") }.max).to eq(9.0)
        expect(json.fetch("metric_catalog").map { |metric| metric.fetch("key") }).to include("metric:queue.depth", "metric_value:queue.depth")
        expect(json.fetch("metric_catalog")).to include(hash_including("key" => "errors.count", "category" => "health"))
        expect(json.fetch("metric_catalog")).to include(hash_including("key" => "metric:queue.depth", "category" => "metrics"))
        catalog_by_key = json.fetch("metric_catalog").index_by { |metric| metric.fetch("key") }
        expect(catalog_by_key.fetch("events.total")).to include("available" => true, "available_events" => 7)
        expect(catalog_by_key.fetch("transactions.p95")).to include("available" => true, "available_events" => 2)
        expect(catalog_by_key.fetch("db.query.avg")).to include("available" => true, "available_events" => 1)
        expect(catalog_by_key.fetch("metric:queue.depth")).to include("available" => true, "available_events" => 2)
        expect(catalog_by_key.fetch("metric_value:queue.depth")).to include("available" => true, "available_events" => 2)
        expect(catalog_by_key.fetch("check_ins.count")).to include("available" => false, "available_events" => 0)
        expect(json.fetch("environments").map { |environment| environment.fetch("name") }).to include("production")
        expect(json.fetch("attributes").map { |attribute| attribute.fetch("key") }).to include("tenant_id", "plan")
        expect(json.fetch("attribute_filters")).to include(hash_including("key" => "tenant_id", "value" => "acme"))
        expect(json.fetch("recent_events").first).to include("environment" => "production")
        expect(json.fetch("recent_events").flat_map { |event| event.fetch("attributes") }.map { |attribute| attribute.fetch("key") }).to include("tenant_id")
      end
    end

    it "caches repeated dashboard data requests for the same project slice" do
      cache_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache_store)

      travel_to Time.zone.local(2026, 5, 21, 12, 0, 0) do
        project = create(:project, user: users(:one), name: "Cached App")
        api_key = create(:api_key, project: project, user: users(:one))
        create(:ingest_event, :log, project: project, api_key: api_key, context: { "environment" => "production" }, occurred_at: 5.minutes.ago)

        expect(ProjectInsights).to receive(:dashboard_for).once.and_call_original

        2.times do
          get insights_data_project_path(project), params: {
            window: "1h",
            environment: "production",
            metrics: [ "events.total" ]
          }

          expect(response).to have_http_status(:success)
        end
      end
    end
  end
end

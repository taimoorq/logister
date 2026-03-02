# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project events", type: :request do
  describe "GET /projects/:project_uuid/events" do
    before { sign_in users(:one) }

    it "redirects to project when not a Turbo Frame request" do
      get project_events_path(projects(:one))
      expect(response).to redirect_to(project_path(projects(:one), filter: "unresolved"))
    end
  end

  describe "GET /projects/:project_uuid/events/:uuid" do
    context "when owner" do
      before { sign_in users(:one) }

      it "returns success and event detail" do
        get project_event_path(projects(:one), ingest_events(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Stacktrace")
        expect(response.body).to include(ingest_events(:one).message)
      end
    end

    context "when shared member" do
      before { sign_in users(:two) }

      it "returns success and event detail" do
        get project_event_path(projects(:one), ingest_events(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(ingest_events(:one).message)
      end
    end

    context "when non-member" do
      before { sign_in users(:one) }

      it "returns 404" do
        get project_event_path(projects(:two), ingest_events(:two))
        expect(response).to have_http_status(:not_found)
      end
    end

    it "renders structured request context when present" do
      sign_in users(:one)
      event = IngestEvent.create!(
        project: projects(:one),
        api_key: api_keys(:one),
        event_type: :error,
        level: "error",
        message: "NoMethodError: undefined method",
        fingerprint: "nomethoderror-structured-context",
        context: {
          clientIp: "66.241.125.180",
          headers: { "Referer" => "https://example.com/page", "Version" => "HTTP/1.1" },
          httpMethod: "GET",
          params: { "page" => "6", "controller" => "blogs", "action" => "show", "id" => "slug" },
          requestId: "d1585398-6817-41cd-bffb-0de457eea5b6",
          url: "https://example.com/content/slug"
        },
        occurred_at: Time.current
      )
      get project_event_path(projects(:one), event)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("clientIp")
      expect(response.body).to include("66.241.125.180")
    end
  end
end

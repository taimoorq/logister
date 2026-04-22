# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Docs", type: :request do
  describe "GET /docs" do
    it "returns success and overview content" do
      get docs_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Logister documentation")
      expect(response.body).to include("Documentation")
      expect(response.body).to include("Public setup guides for Logister and its integrations.")
      expect(response.body).to include("Getting started")
      expect(response.body).to include("Self-hosting")
      expect(response.body).to include("HTTP API")
      expect(response.body).to include("Ruby integration")
      expect(response.body).to include("CFML integration")
      expect(response.body).to include("Integrations")
      expect(response.body).to include("On this page")
      expect(response.body).to include("Growing the docs")
    end
  end

  describe "GET /docs/getting-started" do
    it "returns success and getting started content" do
      get docs_getting_started_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Set up your first Logister project.")
      expect(response.body).to include("Generate an API key")
      expect(response.body).to include("Choose an integration")
      expect(response.body).to include("Integrations")
    end
  end

  describe "GET /docs/self-hosting" do
    it "returns success and self-hosting content" do
      get docs_self_hosting_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Run Logister yourself.")
      expect(response.body).to include("Local quickstart")
      expect(response.body).to include("Production checklist")
    end
  end

  describe "GET /docs/http-api" do
    it "returns success and HTTP API content" do
      get docs_http_api_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("docs-topbar")
      expect(response.body).to include("Send events and check-ins over HTTP.")
      expect(response.body).to include("/api/v1/ingest_events")
      expect(response.body).to include("/api/v1/check_ins")
      expect(response.body).to include("Authorization: Bearer")
    end
  end

  describe "docs layout assets" do
    it "uses the shared stylesheet and importmap tags" do
      get docs_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(rel="stylesheet"))
      if File.exist?(Rails.root.join("app/assets/builds/tailwind.css"))
        expect(response.body).to include("/assets/tailwind")
      end
      expect(response.body).to include(%(type="importmap"))
    end

    it "includes the turbo metadata used by the main app layout" do
      get docs_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(name="turbo-view-transition"))
      expect(response.body).to include(%(name="turbo-refresh-method"))
      expect(response.body).to include(%(name="turbo-refresh-scroll"))
      expect(response.body).to include(%(data-controller="local-time"))
    end
  end

  describe "GET /docs/integrations/ruby" do
    it "returns success and Ruby integration content" do
      get docs_ruby_integration_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Integrate a Ruby or Rails app with Logister.")
      expect(response.body).to include("logister-ruby")
      expect(response.body).to include("Ruby gem")
      expect(response.body).to include("Integrations")
      expect(response.body).to include("Setup flow")
      expect(response.body).to include("bundle install")
    end
  end

  describe "GET /docs/integrations/cfml" do
    it "returns success and CFML integration content" do
      get docs_cfml_integration_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Integrate a Lucee or ColdFusion site with Logister.")
      expect(response.body).to include("Application.cfc.onError()")
      expect(response.body).to include("CFML")
      expect(response.body).to include("Integrations")
      expect(response.body).to include("On this page")
      expect(response.body).to include("Send a structured error event")
    end
  end
end

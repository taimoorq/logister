# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Routes", type: :routing do
  describe "public" do
    it "routes GET / to home#show" do
      expect(get: "/").to route_to(controller: "home", action: "show")
    end
    it "routes GET /about to home#about" do
      expect(get: "/about").to route_to(controller: "home", action: "about")
    end
    it "routes GET /up to rails/health#show" do
      expect(get: "/up").to route_to(controller: "rails/health", action: "show")
    end
  end

  describe "API" do
    it "routes POST /api/v1/ingest_events to api/v1/ingest_events#create" do
      expect(post: "/api/v1/ingest_events").to route_to(
        controller: "api/v1/ingest_events",
        action: "create"
      )
    end

    it "routes POST /api/v1/check_ins to api/v1/check_ins#create" do
      expect(post: "/api/v1/check_ins").to route_to(
        controller: "api/v1/check_ins",
        action: "create"
      )
    end
  end

  describe "health" do
    it "routes GET /health/clickhouse to health#clickhouse" do
      expect(get: "/health/clickhouse").to route_to(
        controller: "health",
        action: "clickhouse"
      )
    end
  end

  describe "projects" do
    it "routes GET /projects/:uuid/settings to project_settings#show" do
      expect(get: "/projects/abc/settings").to route_to(
        controller: "project_settings",
        action: "show",
        uuid: "abc"
      )
    end

    it "routes GET /projects/:uuid/performance to project_performance#show" do
      expect(get: "/projects/abc/performance").to route_to(
        controller: "project_performance",
        action: "show",
        uuid: "abc"
      )
    end

    it "routes GET /projects/:uuid/monitors to project_monitors#show" do
      expect(get: "/projects/abc/monitors").to route_to(
        controller: "project_monitors",
        action: "show",
        uuid: "abc"
      )
    end

    it "routes GET /projects/:uuid/activity to project_activity#show" do
      expect(get: "/projects/abc/activity").to route_to(
        controller: "project_activity",
        action: "show",
        uuid: "abc"
      )
    end
  end
end

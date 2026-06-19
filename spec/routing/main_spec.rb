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
    it "routes GET /privacy to home#privacy" do
      expect(get: "/privacy").to route_to(controller: "home", action: "privacy")
    end
    it "routes GET /cookies to home#cookies" do
      expect(get: "/cookies").to route_to(controller: "home", action: "cookies")
    end
    it "routes Probo cookie banner proxy requests" do
      expect(post: "/api/cookie-banner/v1/banner-1/report").to route_to(
        controller: "cookie_banner_proxy",
        action: "show",
        proxy_path: "banner-1/report"
      )
    end
    it "routes GET /terms to home#terms" do
      expect(get: "/terms").to route_to(controller: "home", action: "terms")
    end
    it "routes GET /robots.txt to home#robots" do
      expect(get: "/robots.txt").to route_to(controller: "home", action: "robots", format: :text)
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

    it "routes POST /api/v1/deployments to api/v1/deployments#create" do
      expect(post: "/api/v1/deployments").to route_to(
        controller: "api/v1/deployments",
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

  describe "github" do
    it "routes GET /github/setup to github/setup#show" do
      expect(get: "/github/setup").to route_to(
        controller: "github/setup",
        action: "show"
      )
    end

    it "routes POST /github/webhooks to github/webhooks#create" do
      expect(post: "/github/webhooks").to route_to(
        controller: "github/webhooks",
        action: "create"
      )
    end

    it "routes POST /projects/:uuid/github/installations/:uuid/sync to github/installations#sync" do
      expect(post: "/projects/project-1/github/installations/install-1/sync").to route_to(
        controller: "github/installations",
        action: "sync",
        project_uuid: "project-1",
        uuid: "install-1"
      )
    end

    it "routes error group GitHub link attachments" do
      expect(post: "/projects/project-1/error_groups/group-1/external_links").to route_to(
        controller: "error_group_external_links",
        action: "create",
        project_uuid: "project-1",
        error_group_uuid: "group-1"
      )
    end

    it "routes error group GitHub link removal" do
      expect(delete: "/projects/project-1/error_groups/group-1/external_links/link-1").to route_to(
        controller: "error_group_external_links",
        action: "destroy",
        project_uuid: "project-1",
        error_group_uuid: "group-1",
        uuid: "link-1"
      )
    end

    it "routes GitHub issue creation for error groups" do
      expect(post: "/projects/project-1/error_groups/group-1/github_issue").to route_to(
        controller: "github/issues",
        action: "create",
        project_uuid: "project-1",
        error_group_uuid: "group-1"
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

    it "routes PATCH /projects/:uuid/rate_limit to project_rate_limits#update" do
      expect(patch: "/projects/abc/rate_limit").to route_to(
        controller: "project_rate_limits",
        action: "update",
        project_uuid: "abc"
      )
    end

    it "routes GET /projects/:uuid/inbox to projects#inbox" do
      expect(get: "/projects/abc/inbox").to route_to(
        controller: "projects",
        action: "inbox",
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

    it "routes project performance frame endpoints" do
      expect(get: "/projects/abc/performance/request-breakdown").to route_to(
        controller: "project_performance",
        action: "request_breakdown",
        uuid: "abc"
      )
      expect(get: "/projects/abc/performance/database-load").to route_to(
        controller: "project_performance",
        action: "database_load",
        uuid: "abc"
      )
      expect(get: "/projects/abc/performance/release-health").to route_to(
        controller: "project_performance",
        action: "release_health",
        uuid: "abc"
      )
      expect(get: "/projects/abc/performance/transactions").to route_to(
        controller: "project_performance",
        action: "transactions",
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

    it "routes GET /projects/:uuid/deployments to project_deployments#index" do
      expect(get: "/projects/abc/deployments").to route_to(
        controller: "project_deployments",
        action: "index",
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

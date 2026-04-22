# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home", type: :request do
  around do |example|
    original_url_options = Rails.application.routes.default_url_options.dup
    example.run
  ensure
    Rails.application.routes.default_url_options = original_url_options
  end

  describe "GET /" do
    context "when unauthenticated" do
      it "returns success and shows landing content" do
        get root_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Keep production calm even when your app is not.")
        expect(response.body).to include("logister-ruby")
        expect(response.body).to include("Start free")
        expect(response.body).to include("<meta name=\"description\"")
        expect(response.body).to include("application/ld+json")
        expect(response.body).to include("&quot;@context&quot;:&quot;https://schema.org&quot;")
        expect(response.body).to include("/llms.txt")
      end

      it "uses the configured https canonical URL even for http requests" do
        Rails.application.routes.default_url_options = { host: "logister.org", protocol: "https" }

        get root_path, headers: { "HOST" => "logister.org" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include('<link rel="canonical" href="https://logister.org/">')
        expect(response.body).to include('<meta property="og:url" content="https://logister.org/">')
        expect(response.body).to include("&quot;url&quot;:&quot;https://logister.org/&quot;")
      end
    end

    context "when authenticated" do
      it "redirects to dashboard" do
        sign_in users(:one)
        get root_path
        expect(response).to redirect_to(dashboard_path)
      end
    end
  end

  describe "GET /about" do
    it "returns success and about content" do
      get about_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("About Logister")
      expect(response.body).to include("<title>About | Logister</title>")
    end
  end

  describe "GET /docs" do
    it "returns success and docs content" do
      get docs_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Documentation")
    end
  end

  describe "GET /privacy" do
    it "returns success and privacy content" do
      get privacy_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Privacy Policy")
    end
  end

  describe "GET /terms" do
    it "returns success and terms content" do
      get terms_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Terms of Use")
    end
  end

  describe "GET /llms.txt" do
    it "returns success and llms content" do
      get "/llms.txt"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Logister is a free, open source bug capture")
    end
  end

  describe "GET /sitemap.xml" do
    it "returns sitemap xml with public pages" do
      get "/sitemap.xml"

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("application/xml")
      expect(response.body).to include("<urlset")
      expect(response.body).to include(root_url)
      expect(response.body).to include(docs_url)
      expect(response.body).to include(docs_getting_started_url)
      expect(response.body).to include(docs_self_hosting_url)
      expect(response.body).to include(docs_local_development_url)
      expect(response.body).to include(docs_deployment_url)
      expect(response.body).to include(docs_clickhouse_url)
      expect(response.body).to include(docs_http_api_url)
      expect(response.body).to include(docs_ruby_integration_url)
      expect(response.body).to include(docs_cfml_integration_url)
      expect(response.body).to include(about_url)
      expect(response.body).to include(privacy_url)
      expect(response.body).to include(terms_url)
    end

    it "uses the configured https host for sitemap entries" do
      Rails.application.routes.default_url_options = { host: "logister.org", protocol: "https" }

      get "/sitemap.xml", headers: { "HOST" => "logister.org" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("<loc>https://logister.org/</loc>")
      expect(response.body).to include("<loc>https://logister.org/docs</loc>")
      expect(response.body).to include("<loc>https://logister.org/docs/getting-started</loc>")
      expect(response.body).to include("<loc>https://logister.org/docs/self-hosting</loc>")
      expect(response.body).to include("<loc>https://logister.org/docs/local-development</loc>")
      expect(response.body).to include("<loc>https://logister.org/docs/deployment</loc>")
      expect(response.body).to include("<loc>https://logister.org/docs/clickhouse</loc>")
      expect(response.body).to include("<loc>https://logister.org/docs/http-api</loc>")
      expect(response.body).to include("<loc>https://logister.org/docs/integrations/ruby</loc>")
      expect(response.body).to include("<loc>https://logister.org/docs/integrations/cfml</loc>")
      expect(response.body).to include("<loc>https://logister.org/about</loc>")
      expect(response.body).to include("<loc>https://logister.org/privacy</loc>")
      expect(response.body).to include("<loc>https://logister.org/terms</loc>")
    end
  end
end

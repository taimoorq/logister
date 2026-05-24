# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

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
        expect(response.body).to include("An open source alternative for teams who want to self-host error monitoring.")
        expect(response.body).to include("Versioned registry images")
        expect(response.body).to include("forkable alternative to Bugsnag, Sentry, and Bugzilla-style workflows")
        expect(response.body).to include("logister-ruby")
        expect(response.body).to include("logister-dotnet")
        expect(response.body).to include("logister-python")
        expect(response.body).to include("Self-host Logister")
        expect(response.body).to include("Use hosted app")
        expect(response.body).to include("https://docs.logister.org/")
        expect(response.body).to include('target="_blank"')
        expect(response.body).to include('rel="noopener noreferrer"')
        expect(response.body).to include("<meta name=\"description\"")
        expect(response.body).to include("<meta name=\"turbo-view-transition\" content=\"true\"")
        expect(response.body).to include("<meta name=\"turbo-refresh-method\" content=\"morph\"")
        expect(response.body).to include("<meta name=\"turbo-refresh-scroll\" content=\"preserve\"")
        expect(response.body).to include("view-transition-name: app-main")
        expect(response.body).to include("application/ld+json")
        expect(response.body).to include("&quot;@context&quot;:&quot;https://schema.org&quot;")
        expect(response.body).to include("/llms.txt")
        expect(response.body).to include("/llms-full.txt")
      end

      it "uses the configured https canonical URL even for http requests" do
        Rails.application.routes.default_url_options = { host: "logister.org", protocol: "https://" }

        get root_path, headers: { "HOST" => "logister.org" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include('<link rel="canonical" href="https://logister.org/">')
        expect(response.body).to include('<meta property="og:url" content="https://logister.org/">')
        expect(response.body).to include("&quot;url&quot;:&quot;https://logister.org/&quot;")
        expect(response.body).not_to include("://://")
      end

      it "loads the public entrypoint without app-only assets" do
        get root_path

        document = Nokogiri::HTML.parse(response.body)
        module_script = document.at_css("script[type='module']")
        preload_hrefs = document.css("link[rel='modulepreload']").map { |node| node["href"].to_s }

        expect(document.at_css("body.public-shell")).to be_present
        expect(module_script&.text).to include('import "public"')
        expect(document.at_css("link[href*='css/tour.min']")).to be_nil
        expect(document.at_css("script[src*='tour'][defer]")).to be_nil
        expect(preload_hrefs.grep(/entrypoints\/(?:authenticated|auth)\b/)).to be_empty
        expect(preload_hrefs.grep(/echarts|controllers\/index/)).to be_empty
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
    it "redirects to the external docs site" do
      get "/docs"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("https://docs.logister.org/")
    end
  end

  describe "GET /docs/product" do
    it "redirects to the external product guide docs page" do
      get "/docs/product"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("https://docs.logister.org/product/")
    end
  end

  describe "GET /docs/metrics" do
    it "redirects to the external metrics reference docs page" do
      get "/docs/metrics"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("https://docs.logister.org/metrics/")
    end
  end

  describe "GET /docs/api-reference" do
    it "redirects to the external API reference docs page" do
      get "/docs/api-reference"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("https://docs.logister.org/api-reference/")
    end
  end

  describe "GET /docs/integrations/javascript" do
    it "redirects to the external JavaScript integration docs page" do
      get "/docs/integrations/javascript"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("https://docs.logister.org/integrations/javascript/")
    end
  end

  describe "GET /docs/integrations/python" do
    it "redirects to the external Python integration docs page" do
      get "/docs/integrations/python"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("https://docs.logister.org/integrations/python/")
    end
  end

  describe "GET /docs/integrations/dotnet" do
    it "redirects to the external .NET integration docs page" do
      get "/docs/integrations/dotnet"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("https://docs.logister.org/integrations/dotnet/")
    end
  end

  describe "GET /privacy" do
    it "returns success and privacy content" do
      get privacy_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Privacy Policy")
      expect(response.body).to include("Application event data")
      expect(response.body).to include(cookies_path)
    end
  end

  describe "GET /cookies" do
    it "returns success and cookie content" do
      get cookies_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Cookie Policy")
      expect(response.body).to include("Strictly necessary cookies")
      expect(response.body).to include("Probo Cookie Banner")
      expect(response.body).to include(privacy_path)
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
      expect(response.body).to include("forkable alternative to Bugsnag, Sentry, and Bugzilla-style workflows")
      expect(response.body).to include("GHCR image package")
      expect(response.body).to include("ghcr.io/taimoorq/logister:v2.2.0")
      expect(response.body).to include("Docker Hub image package")
      expect(response.body).to include("docker.io/taimoorq/logister:v2.2.0")
      expect(response.body).to include("Optional Quay image mirror")
      expect(response.body).to include("https://docs.logister.org/use-cases/")
      expect(response.body).to include("https://docs.logister.org/use-cases/rails-error-monitoring/")
      expect(response.body).to include("https://docs.logister.org/use-cases/python-error-monitoring/")
      expect(response.body).to include("https://docs.logister.org/use-cases/docker-ghcr-self-hosting/")
      expect(response.body).to include("https://docs.logister.org/use-cases/error-assignment-team-triage/")
      expect(response.body).to include("https://docs.logister.org/use-cases/amazon-ses-error-alerts/")
      expect(response.body).to include("https://logister.org/llms-full.txt")
      expect(response.body).to include("Python apps via the `logister-python` package")
      expect(response.body).to include(".NET and ASP.NET Core apps via the `logister-dotnet` SDK")
      expect(response.body).to include("https://docs.logister.org/product/")
      expect(response.body).to include("https://docs.logister.org/integrations/python/")
      expect(response.body).to include("https://docs.logister.org/integrations/dotnet/")
      expect(response.body).to include("https://pypi.org/project/logister-python/")
      expect(response.body).to include("JavaScript and TypeScript apps via the `logister-js` package")
      expect(response.body).to include("CFML apps running on Lucee or Adobe ColdFusion")
      expect(response.body).to include("https://docs.logister.org/integrations/javascript/")
      expect(response.body).to include("https://docs.logister.org/integrations/cfml/")
      expect(response.body).to include("https://www.npmjs.com/package/logister-js")
    end
  end

  describe "GET /llms-full.txt" do
    it "returns success and expanded llms context" do
      get "/llms-full.txt"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Logister Full AI Context")
      expect(response.body).to include("forkable alternative to Bugsnag, Sentry, and Bugzilla-style workflows")
      expect(response.body).to include("Sentry alternative")
      expect(response.body).to include("Rails error monitoring")
      expect(response.body).to include("Docker, GHCR, Docker Hub, and optional Quay self-hosting")
      expect(response.body).to include("Error assignment and team triage")
      expect(response.body).to include("Amazon SES error alert emails")
      expect(response.body).to include("ghcr.io/taimoorq/logister:v2.2.0")
      expect(response.body).to include("docker.io/taimoorq/logister:v2.2.0")
      expect(response.body).to include("quay.io/taimoorq/logister")
      expect(response.body).to include("TRADEMARKS.md")
    end
  end

  describe "GET /robots.txt" do
    it "returns robots rules with configured app and docs sitemap hosts" do
      original_docs_url = ENV["LOGISTER_DOCS_URL"]
      ENV["LOGISTER_DOCS_URL"] = "https://docs.example.test"
      Rails.application.routes.default_url_options = { host: "errors.example.test", protocol: "https://" }

      get "/robots.txt", headers: { "HOST" => "errors.example.test" }

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/plain")
      expect(response.body).to include("Disallow: /admin")
      expect(response.body).to include("Disallow: /api")
      expect(response.body).to include("Allow: /llms.txt")
      expect(response.body).to include("Sitemap: https://errors.example.test/sitemap.xml")
      expect(response.body).to include("Sitemap: https://docs.example.test/sitemap.xml")
      expect(response.body).not_to include("://://")
    ensure
      if original_docs_url
        ENV["LOGISTER_DOCS_URL"] = original_docs_url
      else
        ENV.delete("LOGISTER_DOCS_URL")
      end
    end
  end

  describe "GET /sitemap.xml" do
    it "returns sitemap xml with public pages" do
      get "/sitemap.xml"

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("application/xml")
      expect(response.body).to include("<urlset")
      expect(response.body).to include(root_url)
      expect(response.body).to include(about_url)
      expect(response.body).to include(privacy_url)
      expect(response.body).to include(cookies_url)
      expect(response.body).to include(terms_url)
      expect(response.body).to include("#{root_url}llms.txt")
      expect(response.body).to include("#{root_url}llms-full.txt")
    end

    it "uses the configured https host for sitemap entries" do
      Rails.application.routes.default_url_options = { host: "logister.org", protocol: "https" }

      get "/sitemap.xml", headers: { "HOST" => "logister.org" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("<loc>https://logister.org/</loc>")
      expect(response.body).to include("<loc>https://logister.org/about</loc>")
      expect(response.body).to include("<loc>https://logister.org/privacy</loc>")
      expect(response.body).to include("<loc>https://logister.org/cookies</loc>")
      expect(response.body).to include("<loc>https://logister.org/terms</loc>")
      expect(response.body).to include("<loc>https://logister.org/llms.txt</loc>")
      expect(response.body).to include("<loc>https://logister.org/llms-full.txt</loc>")
    end
  end
end

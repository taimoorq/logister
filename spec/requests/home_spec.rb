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
        expect(response.body).to include("See errors, logs, and app health in one place.")
        expect(response.body).to include("logister-ruby")
        expect(response.body).to include("logister-python")
        expect(response.body).to include("Start free")
        expect(response.body).to include("https://docs.logister.org/")
        expect(response.body).to include('target="_blank"')
        expect(response.body).to include('rel="noopener noreferrer"')
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
    it "redirects to the external docs site" do
      get "/docs"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("https://docs.logister.org/")
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
      expect(response.body).to include("Python apps via the `logister-python` package")
      expect(response.body).to include("https://docs.logister.org/integrations/python/")
      expect(response.body).to include("https://pypi.org/project/logister-python/")
      expect(response.body).to include("JavaScript and TypeScript apps via the `logister-js` package")
      expect(response.body).to include("CFML apps running on Lucee or Adobe ColdFusion")
      expect(response.body).to include("https://docs.logister.org/integrations/javascript/")
      expect(response.body).to include("https://docs.logister.org/integrations/cfml/")
      expect(response.body).to include("https://www.npmjs.com/package/logister-js")
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
      expect(response.body).to include(terms_url)
    end

    it "uses the configured https host for sitemap entries" do
      Rails.application.routes.default_url_options = { host: "logister.org", protocol: "https" }

      get "/sitemap.xml", headers: { "HOST" => "logister.org" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("<loc>https://logister.org/</loc>")
      expect(response.body).to include("<loc>https://logister.org/about</loc>")
      expect(response.body).to include("<loc>https://logister.org/privacy</loc>")
      expect(response.body).to include("<loc>https://logister.org/terms</loc>")
    end
  end
end

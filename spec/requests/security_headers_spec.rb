# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Security headers", type: :request do
  def csp_directives(header = response.headers["Content-Security-Policy"])
    header.to_s.split(";").map(&:strip).to_h do |directive|
      name, *sources = directive.split(/\s+/)
      [ name, sources ]
    end
  end

  def stub_instance_values(values)
    allow(InstanceConfiguration).to receive(:value).and_call_original
    values.each do |key, value|
      allow(InstanceConfiguration).to receive(:value).with(key).and_return(value)
    end
  end

  describe "Content-Security-Policy" do
    it "enforces a nonce-based policy on public pages" do
      get root_path

      expect(response.headers["Content-Security-Policy-Report-Only"]).to be_nil
      directives = csp_directives
      expect(directives["default-src"]).to eq([ "'self'" ])
      expect(directives["object-src"]).to eq([ "'none'" ])
      expect(directives["base-uri"]).to eq([ "'self'" ])
      expect(directives["frame-ancestors"]).to eq([ "'self'" ])
      expect(directives["form-action"]).to eq([ "'self'" ])
      expect(directives["script-src"]).to include("'self'", "https://challenges.cloudflare.com",
                                                  "https://www.googletagmanager.com", "https://static.cloudflareinsights.com")
      expect(directives["script-src"]).not_to include("'unsafe-inline'", "'unsafe-eval'", "https:")
      expect(directives["style-src"]).to include("'self'", "https://fonts.googleapis.com")
      expect(directives["font-src"]).to include("'self'", "https://fonts.gstatic.com")
      expect(directives["frame-src"]).to eq([ "https://challenges.cloudflare.com" ])
      expect(directives["connect-src"]).to include("'self'", "https://cloudflareinsights.com")
    end

    it "stamps the page's inline importmap scripts with the header's nonce" do
      get root_path

      nonce = csp_directives["script-src"].find { |source| source.start_with?("'nonce-") }.to_s.delete_prefix("'nonce-").delete_suffix("'")
      expect(nonce).to be_present
      expect(response.body).to include(%(<meta name="csp-nonce" content="#{nonce}"))
      expect(response.body).to include(%(<script type="importmap" data-turbo-track="reload" nonce="#{nonce}"))
    end

    it "keeps the nonce stable across navigations in one session so Turbo Drive scripts still run" do
      get root_path
      first_nonce = response.body[/<meta name="csp-nonce" content="([^"]+)"/, 1]

      get about_path
      second_nonce = response.body[/<meta name="csp-nonce" content="([^"]+)"/, 1]

      expect(first_nonce).to be_present
      expect(second_nonce).to eq(first_nonce)
    end

    it "applies to signed-in app pages" do
      sign_in create(:user)

      get dashboard_path

      expect(response).to have_http_status(:ok)
      expect(csp_directives["script-src"]).to include("'self'")
      expect(csp_directives["script-src"].grep(/\A'nonce-/)).to be_present
    end

    it "does not create a session cookie for API responses" do
      post "/api/v1/ingest_events", params: {}.to_json, headers: { "CONTENT_TYPE" => "application/json" }

      expect(response.headers["Content-Security-Policy"]).to be_present
      expect(response.headers["Set-Cookie"].to_s).not_to include("_session")
    end

    it "allows only the configured Probo banner script, path-scoped, and its API when not proxied" do
      stub_instance_values(
        "public_site.cookie_banner_script_url" => "https://cdn.jsdelivr.net/npm/@probo/cookie-banner/dist/cookie-banner.iife.js?v=1",
        "public_site.cookie_banner_proxy_enabled" => false,
        "public_site.cookie_banner_base_url" => "https://consent.example.com:8443/api"
      )

      get root_path

      expect(csp_directives["script-src"]).to include("https://cdn.jsdelivr.net/npm/@probo/cookie-banner/dist/cookie-banner.iife.js")
      expect(csp_directives["script-src"]).not_to include("https://cdn.jsdelivr.net")
      expect(csp_directives["connect-src"]).to include("https://consent.example.com:8443")
    end

    it "ignores a non-HTTP banner script URL and allows only Logister's public origin while proxying" do
      stub_instance_values(
        "public_site.cookie_banner_script_url" => "javascript:alert(1)",
        "public_site.cookie_banner_proxy_enabled" => true,
        "public_site.cookie_banner_base_url" => "https://consent.example.com",
        "general.public_url" => "https://errors.example.com"
      )

      get root_path

      expect(response.headers["Content-Security-Policy"]).not_to include("javascript:", "consent.example.com")
      expect(csp_directives["connect-src"]).to include("https://errors.example.com")
    end

    it "is report-only when LOGISTER_CSP_REPORT_ONLY is set" do
      allow_any_instance_of(ActionDispatch::Request).to receive(:content_security_policy_report_only).and_return(true)

      get root_path

      expect(response.headers["Content-Security-Policy"]).to be_nil
      expect(response.headers["Content-Security-Policy-Report-Only"]).to include("object-src 'none'")
    end

    it "reads the report-only switch from the environment at boot" do
      expect(Rails.application.config.content_security_policy_report_only).to be(false)
    end
  end

  describe "Permissions-Policy" do
    it "denies camera, microphone, geolocation, and payment" do
      get root_path

      expect(response.headers["Permissions-Policy"]).to include("camera=()", "microphone=()", "geolocation=()", "payment=()")
    end
  end
end

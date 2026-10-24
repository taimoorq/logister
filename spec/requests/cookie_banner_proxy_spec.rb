# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cookie banner proxy", type: :request do
  around do |example|
    original_banner_id = ENV["PROBO_COOKIE_BANNER_ID"]
    original_base_url = ENV["PROBO_COOKIE_BANNER_BASE_URL"]
    example.run
  ensure
    ENV["PROBO_COOKIE_BANNER_ID"] = original_banner_id
    ENV["PROBO_COOKIE_BANNER_BASE_URL"] = original_base_url
  end

  it "proxies Probo report requests through the app origin" do
    ENV["PROBO_COOKIE_BANNER_ID"] = "banner-1"
    ENV["PROBO_COOKIE_BANNER_BASE_URL"] = "https://probo.example.test/api/cookie-banner/v1"

    upstream_response = upstream_response(
      body: "{\"ok\":true}",
      content_type: "application/json; charset=utf-8",
      status: "201"
    )
    http = instance_double(Net::HTTP)

    expect(http).to receive(:request) do |upstream_request|
      expect(upstream_request).to be_a(Net::HTTP::Post)
      expect(upstream_request.path).to eq("/api/cookie-banner/v1/banner-1/report")
      expect(upstream_request.body).to eq("{\"action\":\"ACCEPT_ALL\"}")
      upstream_response
    end

    expect(Net::HTTP).to receive(:start)
      .with(
        "probo.example.test",
        443,
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 5
      )
      .and_yield(http)

    post "/api/cookie-banner/v1/banner-1/report",
         params: "{\"action\":\"ACCEPT_ALL\"}",
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_ACCEPT" => "application/json",
           "HTTP_USER_AGENT" => "RSpec"
         }

    expect(response).to have_http_status(:created)
    expect(response.media_type).to eq("application/json")
    expect(response.body).to eq("{\"ok\":true}")
  end

  it "does not proxy paths for another banner" do
    ENV["PROBO_COOKIE_BANNER_ID"] = "banner-1"
    ENV["PROBO_COOKIE_BANNER_BASE_URL"] = "https://probo.example.test/api/cookie-banner/v1"

    expect(Net::HTTP).not_to receive(:start)

    post "/api/cookie-banner/v1/other-banner/report", params: "{}"

    expect(response).to have_http_status(:not_found)
  end

  it "does not proxy when the banner proxy setting is disabled" do
    ENV["PROBO_COOKIE_BANNER_ID"] = "banner-1"
    ENV["PROBO_COOKIE_BANNER_BASE_URL"] = "https://probo.example.test/api/cookie-banner/v1"
    InstanceConfiguration.save_section!(
      "public_site",
      values: { "public_site.cookie_banner_proxy_enabled" => "0" },
      clear_keys: [],
      actor: users(:one)
    )

    expect(Net::HTTP).not_to receive(:start)

    get "/api/cookie-banner/v1/banner-1"

    expect(response).to have_http_status(:not_found)
  end

  it "forces a JSON content type and no-store caching on upstream responses" do
    ENV["PROBO_COOKIE_BANNER_ID"] = "banner-1"
    ENV["PROBO_COOKIE_BANNER_BASE_URL"] = "https://probo.example.test/api/cookie-banner/v1"
    upstream = upstream_response(body: "<script>alert(1)</script>", content_type: "text/html", cache_control: "public, max-age=86400")
    http = instance_double(Net::HTTP, request: upstream)
    allow(Net::HTTP).to receive(:start).and_yield(http)

    get "/api/cookie-banner/v1/banner-1"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end

  it "limits proxy requests per source IP" do
    ENV["PROBO_COOKIE_BANNER_ID"] = "banner-1"
    ENV["PROBO_COOKIE_BANNER_BASE_URL"] = "https://probo.example.test/api/cookie-banner/v1"
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    http = instance_double(Net::HTTP, request: upstream_response(body: "{}", content_type: "application/json"))
    allow(Net::HTTP).to receive(:start).and_yield(http)

    CookieBannerProxyController::RATE_LIMIT_REQUESTS.times { get "/api/cookie-banner/v1/banner-1" }
    expect(response).to have_http_status(:ok)

    get "/api/cookie-banner/v1/banner-1"

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq("60")
  end

  def upstream_response(body:, content_type:, status: "200", cache_control: nil)
    instance_double(
      Net::HTTPResponse,
      body: body,
      code: status,
      "[]" => nil
    ).tap do |response|
      allow(response).to receive(:[]).with("Cache-Control").and_return(cache_control)
      allow(response).to receive(:[]).with("Content-Type").and_return(content_type)
    end
  end
end

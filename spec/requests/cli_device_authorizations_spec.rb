# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CLI device authorization", type: :request do
  let(:user) { create(:user) }
  let!(:project) { create(:project, user: user, name: "Checkout API", slug: "checkout-api") }

  it "approves a browser-backed CLI login and exchanges it for a read token" do
    post "/api/v1/cli/device_authorizations",
         params: { client_name: "Logister CLI", scopes: CliAccessToken::READ_SCOPES }

    expect(response).to have_http_status(:created)
    authorization_payload = response.parsed_body
    expect(authorization_payload["device_code"]).to be_present
    expect(authorization_payload["user_code"]).to match(/\A[A-Z0-9]{4}-[A-Z0-9]{4}\z/)
    expect(authorization_payload["verification_uri"]).to end_with("/cli/device")
    expect(authorization_payload["verification_uri_complete"]).to include("user_code=")
    expect(authorization_payload["scopes"]).to eq(CliAccessToken::READ_SCOPES)
    expect(authorization_payload["scope"].split).to eq(CliAccessToken::READ_SCOPES)

    post "/api/v1/cli/device_authorizations/token", params: { device_code: authorization_payload["device_code"] }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("authorization_pending")

    sign_in user
    get "/cli/device", params: { user_code: authorization_payload["user_code"] }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("traces:read", "metrics:read", "Requested access", "Read-only.")

    post "/cli/device",
         params: {
           user_code: authorization_payload["user_code"],
           decision: "approve",
           project_ids: [ project.id.to_s ]
         }

    expect(response).to redirect_to("/cli/device?user_code=#{authorization_payload['user_code']}")

    post "/api/v1/cli/device_authorizations/token", params: { device_code: authorization_payload["device_code"] }

    expect(response).to have_http_status(:ok)
    token_payload = response.parsed_body
    expect(token_payload["access_token"]).to start_with("logister_cli_")
    expect(token_payload["token_type"]).to eq("Bearer")
    expect(token_payload["scope"].split).to match_array(CliAccessToken::READ_SCOPES)
    expect(token_payload["scopes"]).to eq(CliAccessToken::READ_SCOPES)

    get "/api/v1/cli/projects", headers: { "Authorization" => "Bearer #{token_payload['access_token']}" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["items"].pluck("slug")).to eq([ "checkout-api" ])
  end

  it "lets a signed-in user deny a CLI login request" do
    authorization = create(:cli_device_authorization)

    sign_in user
    post "/cli/device", params: { user_code: authorization.user_code_display, decision: "deny" }

    expect(response).to redirect_to("/cli/device?user_code=#{authorization.user_code_display}")
    expect(authorization.reload).to be_denied
  end

  it "rejects expired or unknown device codes during polling" do
    expired = create(:cli_device_authorization, :expired, device_code: "expired-device-code")

    post "/api/v1/cli/device_authorizations/token", params: { device_code: "expired-device-code" }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("expired_token")

    post "/api/v1/cli/device_authorizations/token", params: { device_code: "missing-device-code" }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("invalid_grant")

    expect(expired.reload.cli_access_token).to be_nil
  end

  it "rate limits device creation by hashed IP" do
    cache = ActiveSupport::Cache::MemoryStore.new
    allow(Rails.application.config.x.logister).to receive(:rate_limit_cache).and_return(cache)
    stub_const("Api::V1::Cli::DeviceRateLimitGuard::CREATE_LIMIT", 1)

    post "/api/v1/cli/device_authorizations", params: { client_name: "first" }
    expect(response).to have_http_status(:created)

    post "/api/v1/cli/device_authorizations", params: { client_name: "second" }
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body["code"]).to eq("rate_limited")
    expect(cache.instance_variable_get(:@data).keys.join).not_to include(request.remote_ip.to_s)
  end

  it "keeps device creation and token polling limited through the fallback during a store outage" do
    allow(Rails.application.config.x.logister).to receive(:rate_limit_cache).and_return(unavailable_rate_limit_store)
    stub_const("Api::V1::Cli::DeviceRateLimitGuard::CREATE_LIMIT", 1)
    stub_const("Api::V1::Cli::DeviceRateLimitGuard::TOKEN_LIMIT", 1)

    post "/api/v1/cli/device_authorizations", params: { client_name: "first" }
    expect(response).to have_http_status(:created)
    post "/api/v1/cli/device_authorizations", params: { client_name: "second" }
    expect(response).to have_http_status(:too_many_requests)

    post "/api/v1/cli/device_authorizations/token", params: { device_code: "missing" }
    expect(response).to have_http_status(:bad_request)
    post "/api/v1/cli/device_authorizations/token", params: { device_code: "missing" }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "fails closed for device creation and token polling when no rate-limit store can count" do
    allow(Rails.application.config.x.logister).to receive(:rate_limit_cache).and_return(unavailable_rate_limit_store)
    break_rate_limit_fallback_store!

    expect {
      post "/api/v1/cli/device_authorizations", params: { client_name: "outage" }
    }.not_to change(CliDeviceAuthorization, :count)
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq("60")

    post "/api/v1/cli/device_authorizations/token", params: { device_code: "missing" }
    expect(response).to have_http_status(:too_many_requests)
  end

  describe "browser approval page" do
    let(:authorization) { create(:cli_device_authorization, client_name: "Totally Official CLI") }

    before { sign_in user }

    it "pre-fills the code from verification_uri_complete and warns before approval" do
      get "/cli/device", params: { user_code: authorization.user_code_display }

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      warning = page.at_css("[role='alert']")
      expect(warning.text).to include("Approve only if you started this login from your own terminal just now.")
      expect(warning.text).to include("Requested", "Requested from IP")
      expect(warning.at_css("time[datetime='#{authorization.created_at.utc.iso8601(3)}']")).to be_present
      expect(page.text).to include("Client name (self-reported):", "Totally Official CLI")
      expect(page.at_css("input[name='user_code'][type='hidden']")["value"]).to eq(authorization.user_code_display)
    end

    it "shows the IP that requested the device code" do
      skip "requested_ip column is added by a separate migration" unless CliDeviceAuthorization.column_names.include?("requested_ip")

      post "/api/v1/cli/device_authorizations", params: { client_name: "Logister CLI" }, env: { "REMOTE_ADDR" => "198.51.100.23" }
      user_code = response.parsed_body.fetch("user_code")

      get "/cli/device", params: { user_code: user_code }

      expect(Nokogiri::HTML(response.body).at_css("[role='alert']").text).to include("198.51.100.23")
    end

    it "leaves every project unchecked by default" do
      create(:project, user: user, name: "Billing API", slug: "billing-api")

      get "/cli/device", params: { user_code: authorization.user_code_display }

      checkboxes = Nokogiri::HTML(response.body).css("input[type='checkbox']")
      expect(checkboxes.map { |box| box["name"] }).to include("all_projects", "project_ids[]")
      expect(checkboxes.select { |box| box["checked"] }).to be_empty
    end

    it "describes upload access when the request includes artifacts:write" do
      upload_request = create(:cli_device_authorization, requested_scopes: [ "projects:read", "artifacts:write" ])

      get "/cli/device", params: { user_code: upload_request.user_code_display }

      expect(response.body).to include("upload Android mapping files and Apple dSYM symbol files")
      expect(response.body).not_to include("Read-only.")
    end

    it "requires at least one project selection to approve" do
      post "/cli/device", params: { user_code: authorization.user_code_display, decision: "approve" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must include at least one project")
      expect(authorization.reload).to be_pending
    end

    it "approves only when the decision is approve" do
      [ nil, "", "yes", "APPROVE" ].each do |decision|
        post "/cli/device", params: { user_code: authorization.user_code_display, decision: decision, project_ids: [ project.id ] }.compact

        expect(response).to redirect_to("/cli/device?user_code=#{authorization.user_code_display}")
        expect(flash[:alert]).to eq("Choose Approve or Deny to answer this CLI login request.")
        expect(authorization.reload).to be_pending
      end

      post "/cli/device", params: { user_code: authorization.user_code_display, decision: "approve", project_ids: [ project.id ] }

      expect(authorization.reload).to be_approved
      expect(authorization.approved_project_ids).to eq([ project.id ])
    end
  end

  describe "browser approval rate limits" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails.application.config.x.logister).to receive(:rate_limit_cache).and_return(cache)
      sign_in user
    end

    it "limits user code lookups per signed-in user" do
      stub_const("CliDeviceApprovalRateLimitGuard::LIMITS", { "lookup" => { user: 2, ip: 100 }, "decision" => { user: 100, ip: 100 } })

      2.times do |index|
        get "/cli/device", params: { user_code: "GUES-S00#{index}" }
        expect(response).to have_http_status(:ok)
      end

      get "/cli/device", params: { user_code: "GUES-S009" }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to eq(10.minutes.to_i.to_s)
      expect(response.body).to include("Too many CLI login code attempts.")
      expect(cache.instance_variable_get(:@data).keys.join).not_to include("user:#{user.id}", request.remote_ip.to_s)
    end

    it "limits user code lookups per IP across accounts" do
      stub_const("CliDeviceApprovalRateLimitGuard::LIMITS", { "lookup" => { user: 100, ip: 1 }, "decision" => { user: 100, ip: 100 } })

      get "/cli/device", params: { user_code: "GUES-S001" }
      expect(response).to have_http_status(:ok)

      sign_in create(:user)
      get "/cli/device", params: { user_code: "GUES-S002" }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "does not count the empty code entry page" do
      stub_const("CliDeviceApprovalRateLimitGuard::LIMITS", { "lookup" => { user: 1, ip: 1 }, "decision" => { user: 1, ip: 1 } })

      3.times { get "/cli/device" }

      expect(response).to have_http_status(:ok)
    end

    it "limits approval decisions without changing the authorization" do
      stub_const("CliDeviceApprovalRateLimitGuard::LIMITS", { "lookup" => { user: 100, ip: 100 }, "decision" => { user: 1, ip: 100 } })
      authorization = create(:cli_device_authorization)

      post "/cli/device", params: { user_code: "WRON-GCOD", decision: "approve", project_ids: [ project.id ] }
      expect(response).to redirect_to("/cli/device")

      post "/cli/device", params: { user_code: authorization.user_code_display, decision: "approve", project_ids: [ project.id ] }

      expect(response).to have_http_status(:too_many_requests)
      expect(authorization.reload).to be_pending
    end

    it "fails closed for lookups and decisions when no rate-limit store can count" do
      allow(Rails.application.config.x.logister).to receive(:rate_limit_cache).and_return(unavailable_rate_limit_store)
      break_rate_limit_fallback_store!
      authorization = create(:cli_device_authorization)

      get "/cli/device", params: { user_code: authorization.user_code_display }
      expect(response).to have_http_status(:too_many_requests)

      post "/cli/device", params: { user_code: authorization.user_code_display, decision: "approve", project_ids: [ project.id ] }
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to be_present
      expect(authorization.reload).to be_pending
    end
  end
end

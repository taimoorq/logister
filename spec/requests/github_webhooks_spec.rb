# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GitHub webhooks", type: :request do
  let(:payload) { { "zen" => "Keep it logically awesome." }.to_json }

  before do
    allow(Logister::GithubAppConfig).to receive(:webhook_secret).and_return("secret")
  end

  it "accepts valid signed webhook deliveries" do
    result = Github::InstallationSync::Result.new(status: :pong, installation: nil, repositories: [])
    allow(Github::InstallationSync).to receive(:from_webhook).and_return(result)

    post github_webhooks_path,
         params: payload,
         headers: signed_headers(payload, event: "ping")

    expect(response).to have_http_status(:accepted)
    expect(Github::InstallationSync).to have_received(:from_webhook).with(
      event: "ping",
      payload: JSON.parse(payload)
    )
  end

  it "rejects invalid signatures" do
    allow(Github::InstallationSync).to receive(:from_webhook)

    post github_webhooks_path,
         params: payload,
         headers: signed_headers(payload, signature: "sha256=bad")

    expect(response).to have_http_status(:unauthorized)
    expect(Github::InstallationSync).not_to have_received(:from_webhook)
  end

  it "returns service unavailable when no webhook secret is configured" do
    allow(Logister::GithubAppConfig).to receive(:webhook_secret).and_return(nil)

    post github_webhooks_path,
         params: payload,
         headers: signed_headers(payload)

    expect(response).to have_http_status(:service_unavailable)
  end

  it "returns bad request for malformed JSON with a valid signature" do
    malformed_payload = "{bad"

    post github_webhooks_path,
         params: malformed_payload,
         headers: signed_headers(malformed_payload)

    expect(response).to have_http_status(:bad_request)
  end

  def signed_headers(payload, event: "ping", signature: nil)
    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_GITHUB_EVENT" => event,
      "HTTP_X_HUB_SIGNATURE_256" => signature || signature_for(payload)
    }
  end

  def signature_for(payload)
    "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", "secret", payload)}"
  end
end

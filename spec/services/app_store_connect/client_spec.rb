# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppStoreConnect::Client do
  let(:setting) do
    instance_double(
      ProjectIntegrationSetting,
      account_id: "issuer-123",
      external_project_name: "KEY123",
      credential_reference: "APP_STORE_CONNECT_PRIVATE_KEY"
    )
  end
  let(:http) { instance_double(Net::HTTP) }
  let(:credential_resolver) { instance_double(AppStoreConnect::CredentialResolver, token: "store-token") }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(AppStoreConnect::CredentialResolver).to receive(:new).and_return(credential_resolver)
  end

  it "resolves one bundle ID and requests the iOS performance report" do
    requests = []
    responses = [
      success_response("data" => [ { "id" => "apple-app-1", "attributes" => { "bundleId" => "com.acme.shop" } } ]),
      success_response("productData" => [])
    ]
    allow(http).to receive(:request) do |request|
      requests << request
      responses.shift
    end
    client = described_class.new(setting)

    app = client.app_for_bundle_id("com.acme.shop")
    report = client.performance_metrics(app.fetch("id"))

    expect(URI.decode_www_form(requests.first.uri.query).to_h).to eq("filter[bundleId]" => "com.acme.shop", "limit" => "2")
    expect(requests.second.uri.path).to eq("/v1/apps/apple-app-1/perfPowerMetrics")
    expect(URI.decode_www_form(requests.second.uri.query).to_h).to eq("filter[platform]" => "IOS")
    expect(requests.map { |request| request["Authorization"] }).to eq([ "Bearer store-token", "Bearer store-token" ])
    expect(report).to eq("productData" => [])
  end

  it "surfaces API detail and retry timing without exposing credentials" do
    response = Net::HTTPTooManyRequests.new("1.1", "429", "Too Many Requests")
    response["Retry-After"] = "60"
    response.instance_variable_set(:@body, { "errors" => [ { "detail" => "Rate limit reached" } ] }.to_json)
    response.instance_variable_set(:@read, true)
    allow(http).to receive(:request).and_return(response)

    expect { described_class.new(setting).app_for_bundle_id("com.acme.shop") }
      .to raise_error(AppStoreConnect::Client::Error, /429.*Rate limit reached.*retry after 60 seconds/)
  end

  def success_response(payload)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@body, payload.to_json)
    response.instance_variable_set(:@read, true)
    response
  end
end

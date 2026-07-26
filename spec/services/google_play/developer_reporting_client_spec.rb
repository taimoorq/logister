# frozen_string_literal: true

require "rails_helper"

RSpec.describe GooglePlay::DeveloperReportingClient do
  let(:http) { instance_double(Net::HTTP) }
  let(:credential_resolver) { instance_double(GooglePlay::CredentialResolver, access_token: "play-token") }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(GooglePlay::CredentialResolver).to receive(:new).and_return(credential_resolver)
  end

  it "queries supported version-code dimensions and paginates metric rows" do
    requests = []
    responses = [
      success_response("rows" => [ metric_row("42") ], "nextPageToken" => "next-page"),
      success_response("rows" => [ metric_row("43") ])
    ]
    allow(http).to receive(:request) do |request|
      requests << request
      responses.shift
    end

    result = described_class.new(credential_reference: "PLAY_CREDENTIALS").crash_rates(
      "com.acme.shop",
      start_date: Date.new(2026, 7, 1),
      end_date: Date.new(2026, 7, 2)
    )

    bodies = requests.map { |request| JSON.parse(request.body) }
    expect(bodies.first).to include(
      "dimensions" => [ "versionCode" ],
      "metrics" => %w[crashRate userPerceivedCrashRate distinctUsers],
      "pageSize" => 1_000
    )
    expect(bodies.first).not_to include("pageToken")
    expect(bodies.second["pageToken"]).to eq("next-page")
    expect(result.fetch("rows").size).to eq(2)
  end

  it "paginates anomaly collections with query parameters" do
    requests = []
    responses = [
      success_response("anomalies" => [ { "name" => "one" } ], "nextPageToken" => "more"),
      success_response("anomalies" => [ { "name" => "two" } ])
    ]
    allow(http).to receive(:request) do |request|
      requests << request
      responses.shift
    end

    result = described_class.new(credential_reference: "PLAY_CREDENTIALS").anomalies("com.acme.shop")

    expect(URI.decode_www_form(requests.first.uri.query).to_h).to eq("pageSize" => "1000")
    expect(URI.decode_www_form(requests.second.uri.query).to_h).to eq("pageSize" => "1000", "pageToken" => "more")
    expect(result.fetch("anomalies").pluck("name")).to eq(%w[one two])
  end

  def metric_row(version_code)
    { "dimensions" => [ { "dimension" => "versionCode", "int64Value" => version_code } ] }
  end

  def success_response(payload)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@body, payload.to_json)
    response.instance_variable_set(:@read, true)
    response
  end
end

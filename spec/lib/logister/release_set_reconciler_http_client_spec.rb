# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ReleaseSetReconciler::HttpClient do
  def authorization_sent_to(url, client)
    sent = nil
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request) do |request|
      sent = request["Authorization"]
      instance_double(Net::HTTPOK, code: "200", body: "{}", is_a?: false)
    end
    allow(Net::HTTP).to receive(:start).and_yield(http)

    client.get(url)
    sent
  end

  let(:client) { described_class.new(github_token: "", health_token: "health-secret") }

  it "sends the health token to the production health report" do
    expect(authorization_sent_to("https://logister.org/health/release", client)).to eq("Bearer health-secret")
  end

  it "never sends the health token to other hosts or paths" do
    expect(authorization_sent_to("https://registry.npmjs.org/logister-cli/1.0.0", client)).to be_nil
    expect(authorization_sent_to("https://logister.org/releases/receipt.json", client)).to be_nil
    expect(authorization_sent_to("http://logister.org/health/release", client)).to be_nil
  end
end

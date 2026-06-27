# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientSubmissions::TokenExtractor, type: :model do
  it "extracts bearer tokens before X-Api-Key tokens" do
    request = instance_double(
      ActionDispatch::Request,
      headers: {
        "Authorization" => "Bearer bearer-token ",
        "X-Api-Key" => "api-key-token"
      }
    )

    result = described_class.call(request)

    expect(result.token).to eq("bearer-token")
    expect(result.source).to eq("authorization_bearer")
  end

  it "extracts X-Api-Key when no bearer token is present" do
    request = instance_double(ActionDispatch::Request, headers: { "X-Api-Key" => " api-key-token " })

    result = described_class.call(request)

    expect(result.token).to eq("api-key-token")
    expect(result.source).to eq("x_api_key")
  end

  it "returns a blank result when no supported credential is present" do
    request = instance_double(ActionDispatch::Request, headers: {})

    result = described_class.call(request)

    expect(result.token).to be_nil
    expect(result.source).to be_nil
  end
end

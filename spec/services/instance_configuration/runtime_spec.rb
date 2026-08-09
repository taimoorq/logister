# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstanceConfiguration::Runtime, type: :model do
  it "applies saved public API limits and request thresholds without an environment-only path" do
    config = Rails.application.config.x.logister
    original_values = {
      public_api_rate_limit_requests: config.public_api_rate_limit_requests,
      public_api_rate_limit_period_seconds: config.public_api_rate_limit_period_seconds,
      public_api_pre_auth_rate_limit_requests: config.public_api_pre_auth_rate_limit_requests,
      public_api_auth_failure_rate_limit_requests: config.public_api_auth_failure_rate_limit_requests,
      web_request_min_duration_ms: config.web_request_min_duration_ms,
      web_request_log_min_duration_ms: config.web_request_log_min_duration_ms
    }
    InstanceConfiguration.save_section!(
      "authentication",
      values: {
        "authentication.public_api_rate_limit_requests" => "777",
        "authentication.public_api_rate_limit_period_seconds" => "45",
        "authentication.public_api_pre_auth_rate_limit_requests" => "5555",
        "authentication.public_api_auth_failure_rate_limit_requests" => "33"
      },
      clear_keys: [],
      actor: users(:one)
    )
    InstanceConfiguration.save_section!(
      "observability",
      values: {
        "observability.web_request_min_duration_ms" => "175",
        "observability.web_request_log_min_duration_ms" => "825"
      },
      clear_keys: [],
      actor: users(:one)
    )

    described_class.apply_operational_limits!

    expect(config.public_api_rate_limit_requests).to eq(777)
    expect(config.public_api_rate_limit_period_seconds).to eq(45)
    expect(config.public_api_pre_auth_rate_limit_requests).to eq(5555)
    expect(config.public_api_auth_failure_rate_limit_requests).to eq(33)
    expect(config.web_request_min_duration_ms).to eq(175.0)
    expect(config.web_request_log_min_duration_ms).to eq(825.0)
  ensure
    original_values&.each { |key, value| config.public_send("#{key}=", value) }
  end
end

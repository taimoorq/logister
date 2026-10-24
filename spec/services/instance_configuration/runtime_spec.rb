# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstanceConfiguration::Runtime, type: :model do
  it "applies saved public API limits while keeping self request telemetry disabled without an environment-only path" do
    config = Rails.application.config.x.logister
    original_values = {
      public_api_rate_limit_requests: config.public_api_rate_limit_requests,
      public_api_rate_limit_period_seconds: config.public_api_rate_limit_period_seconds,
      public_api_pre_auth_rate_limit_requests: config.public_api_pre_auth_rate_limit_requests,
      public_api_auth_failure_rate_limit_requests: config.public_api_auth_failure_rate_limit_requests,
      web_request_transactions_enabled: config.web_request_transactions_enabled
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
    expect(config.web_request_transactions_enabled).to be(false)
  ensure
    original_values&.each { |key, value| config.public_send("#{key}=", value) }
  end

  it "re-raises rate-limit store errors so limiters fall back instead of reading a swallowed error as unlimited" do
    config = Rails.application.config.x.logister
    original_cache = Rails.cache
    original_rate_limit_cache = config.rate_limit_cache
    store_options = {}
    allow(Rails.env).to receive(:test?).and_return(false)
    allow(ActiveSupport::Cache).to receive(:lookup_store) do |_store, options|
      store_options[options.fetch(:namespace)] = options
      ActiveSupport::Cache::MemoryStore.new
    end

    described_class.apply_cache!

    cache_handler = store_options.find { |namespace, _| namespace.start_with?("logister:cache:") }.last.fetch(:error_handler)
    rate_limit_handler = store_options.find { |namespace, _| namespace.start_with?("logister:rate_limit:") }.last.fetch(:error_handler)
    error = Errno::ECONNREFUSED.new("redis down")

    expect { cache_handler.call(method: :read, returning: nil, exception: error) }.not_to raise_error
    expect { rate_limit_handler.call(method: :increment, returning: nil, exception: error) }.to raise_error(error)
  ensure
    Rails.cache = original_cache
    config.rate_limit_cache = original_rate_limit_cache
  end
end

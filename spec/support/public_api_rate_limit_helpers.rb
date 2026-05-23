# frozen_string_literal: true

module PublicApiRateLimitHelpers
  def with_public_api_rate_limits(requests: 1_200, auth_failure_requests: 120, period_seconds: 60)
    logister_config = Rails.application.config.x.logister
    previous_values = {
      public_api_rate_limit_requests: logister_config.public_api_rate_limit_requests,
      public_api_rate_limit_period_seconds: logister_config.public_api_rate_limit_period_seconds,
      public_api_auth_failure_rate_limit_requests: logister_config.public_api_auth_failure_rate_limit_requests
    }

    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    logister_config.public_api_rate_limit_requests = requests
    logister_config.public_api_rate_limit_period_seconds = period_seconds
    logister_config.public_api_auth_failure_rate_limit_requests = auth_failure_requests

    yield
  ensure
    previous_values&.each do |name, value|
      logister_config.public_send("#{name}=", value)
    end
  end
end

RSpec.configure do |config|
  config.include PublicApiRateLimitHelpers, type: :request
end

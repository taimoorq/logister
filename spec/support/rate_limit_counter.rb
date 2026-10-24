# frozen_string_literal: true

module RateLimitStoreHelpers
  # A cache double that fails every call, like a Redis store during an outage.
  def unavailable_rate_limit_store(message = "rate-limit store unavailable")
    Class.new do
      define_method(:increment) { |*, **| raise Errno::ECONNREFUSED, message }
      define_method(:write) { |*, **| raise Errno::ECONNREFUSED, message }
    end.new
  end

  # Makes the in-process fallback fail too, so limiters must fail closed.
  def break_rate_limit_fallback_store!
    allow(Logister::RateLimitCounter).to receive(:fallback_store).and_return(unavailable_rate_limit_store("fallback unavailable"))
  end
end

RSpec.configure do |config|
  config.include RateLimitStoreHelpers

  # The in-process fallback store lives for the whole test process. Clear it so
  # counts from a simulated outage never leak into the next example.
  config.before do
    Logister::RateLimitCounter.reset_fallback_store!
  end
end

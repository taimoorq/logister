# frozen_string_literal: true

module SqlCapture
  def capture_sql
    queries = []
    callback = lambda do |*, payload|
      queries << payload[:sql] unless payload[:cached] || %w[SCHEMA CACHE TRANSACTION].include?(payload[:name])
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end
end

RSpec.configure { |config| config.include SqlCapture }

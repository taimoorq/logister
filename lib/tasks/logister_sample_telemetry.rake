# frozen_string_literal: true

require "json"

namespace :logister do
  desc "Send one sample error, log, metric, transaction, span set, check-in, and deployment through logister-ruby"
  task sample_telemetry: :environment do
    result = Logister::SampleTelemetryReporter.call
    puts JSON.pretty_generate(result)
  end
end

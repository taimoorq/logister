require "logger"

module Logister
  class Configuration
    attr_accessor :api_key, :endpoint, :environment, :service, :release, :enabled, :timeout_seconds, :logger

    def initialize
      @api_key = ENV["LOGISTER_API_KEY"]
      @endpoint = ENV.fetch("LOGISTER_ENDPOINT", "https://logister.org/api/v1/ingest_events")
      @environment = ENV.fetch("RAILS_ENV", ENV.fetch("RACK_ENV", "development"))
      @service = ENV.fetch("LOGISTER_SERVICE", "ruby-app")
      @release = ENV["LOGISTER_RELEASE"]
      @enabled = true
      @timeout_seconds = 2
      @logger = Logger.new($stdout)
      @logger.level = Logger::WARN
    end
  end
end

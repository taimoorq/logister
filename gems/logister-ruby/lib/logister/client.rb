require "json"
require "net/http"
require "uri"

module Logister
  class Client
    def initialize(configuration)
      @configuration = configuration
    end

    def publish(payload)
      return false unless ready?

      uri = URI.parse(@configuration.endpoint)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@configuration.api_key}"
      request.body = { event: payload }.to_json

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: @configuration.timeout_seconds,
        read_timeout: @configuration.timeout_seconds
      ) { |http| http.request(request) }

      response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      @configuration.logger.warn("logister publish failed: #{e.class} #{e.message}")
      false
    end

    private

    def ready?
      @configuration.enabled && @configuration.api_key.to_s != ""
    end
  end
end

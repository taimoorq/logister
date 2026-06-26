# frozen_string_literal: true

require "net/http"

module Logister
  class HttpClient
    def self.request(uri, request, open_timeout:, read_timeout:, use_ssl: nil)
      start(uri, open_timeout: open_timeout, read_timeout: read_timeout, use_ssl: use_ssl) do |http|
        http.request(request)
      end
    end

    def self.start(uri, open_timeout:, read_timeout:, use_ssl: nil)
      Net::HTTP.start(
        uri.hostname || uri.host,
        uri.port,
        use_ssl: use_ssl.nil? ? uri.scheme == "https" : use_ssl,
        open_timeout: open_timeout,
        read_timeout: read_timeout
      ) do |http|
        yield http
      end
    end
  end
end

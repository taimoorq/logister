require "json"
require "net/http"
require "uri"

module Logister
  class ClickhouseClient
    class Error < StandardError; end
    HEALTH_CACHE_TTL = 30.seconds

    def initialize(config: Rails.configuration.x.logister)
      @config = config
    end

    def enabled?
      @config.clickhouse_enabled
    end

    def insert_event!(attributes)
      return unless enabled?

      query = "INSERT INTO #{full_table_name} FORMAT JSONEachRow"
      body = "#{attributes.to_json}\n"

      response = post_query(query, body)
      return if response.is_a?(Net::HTTPSuccess)

      raise Error, "ClickHouse insert failed: #{response.code} #{response.body.to_s.strip}"
    end

    def healthy?
      return false unless enabled?

      Rails.cache.fetch(health_cache_key, expires_in: HEALTH_CACHE_TTL) do
        response = post_query("SELECT 1 FORMAT TabSeparated", "")
        response.is_a?(Net::HTTPSuccess) && (query_api_mode? || response.body.to_s.strip == "1")
      end
    rescue StandardError
      false
    end

    private

    def full_table_name
      "#{@config.clickhouse_database}.#{@config.clickhouse_events_table}"
    end

    def post_query(query, body)
      uri = build_uri(query)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.basic_auth(@config.clickhouse_username, @config.clickhouse_password) if @config.clickhouse_username.present?
      request.body = request_body(query, body)

      with_http_connection(uri) do |http|
        http.request(request)
      end
    end

    def request_body(query, body)
      if query_api_mode?
        { sql: "#{query}\n#{body}" }.to_json
      else
        body
      end
    end

    def build_uri(query)
      uri = URI.parse(@config.clickhouse_url)
      uri.query = URI.encode_www_form(query: query) unless query_api_mode?
      uri
    end

    def query_api_mode?
      uri = URI.parse(@config.clickhouse_url)
      uri.host == "queries.clickhouse.cloud"
    end

    def health_cache_key
      [ "clickhouse", "health", @config.clickhouse_url, @config.clickhouse_database, @config.clickhouse_events_table ]
    end

    def with_http_connection(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 2
      http.read_timeout = 5
      http.start
      yield http
    ensure
      http&.finish if http&.active?
    end
  end
end

require "json"
require "net/http"
require "uri"

module Logister
  class ClickhouseClient
    class Error < StandardError; end

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

      response = post_query("SELECT 1 FORMAT TabSeparated", "")
      response.is_a?(Net::HTTPSuccess) && response.body.to_s.strip == "1"
    rescue StandardError
      false
    end

    private

    def full_table_name
      "#{@config.clickhouse_database}.#{@config.clickhouse_events_table}"
    end

    def post_query(query, body)
      uri = URI.parse(@config.clickhouse_url)
      uri.query = URI.encode_www_form(query: query)

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.basic_auth(@config.clickhouse_username, @config.clickhouse_password) if @config.clickhouse_username.present?
      request.body = body

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 2, read_timeout: 5) do |http|
        http.request(request)
      end
    end
  end
end

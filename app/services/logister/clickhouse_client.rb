require "json"
require "net/http"
require "uri"

module Logister
  class ClickhouseClient
    class Error < StandardError; end
    HEALTH_CACHE_TTL = 30.seconds
    SCHEMA_CACHE_TTL = 30.seconds
    IDENTIFIER_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/
    REQUIRED_TABLES = %w[
      events_raw
      events_1m
      mv_events_1m
      spans_raw
      request_spans_1m
      mv_request_spans_1m
    ].freeze

    def initialize(config: Rails.configuration.x.logister)
      @config = config
    end

    def enabled?
      @config.clickhouse_enabled
    end

    def insert_event!(attributes)
      insert_row!(@config.clickhouse_events_table, attributes)
    end

    def insert_span!(attributes)
      insert_row!(@config.clickhouse_spans_table, attributes)
    end

    def select_rows!(query)
      return [] unless enabled?

      formatted_query = query.match?(/\bFORMAT\s+JSONEachRow\b/i) ? query : "#{query} FORMAT JSONEachRow"
      response = post_query(formatted_query, "")
      return parse_json_each_row(response.body) if response.is_a?(Net::HTTPSuccess)

      raise Error, "ClickHouse query failed: #{response.code} #{response.body.to_s.strip}"
    end

    def execute!(query)
      return "" unless enabled?

      response = post_query(query, "")
      return response.body.to_s if response.is_a?(Net::HTTPSuccess)

      raise Error, "ClickHouse query failed: #{response.code} #{response.body.to_s.strip}"
    end

    def load_schema!(schema_sql)
      statements = schema_statements(schema_sql)
      statements.each { |statement| execute!(statement) }
      statements.length
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

    def ready?
      schema_status.fetch(:ready)
    end

    def schema_status
      return disabled_schema_status unless enabled?

      Rails.cache.fetch(schema_cache_key, expires_in: SCHEMA_CACHE_TTL) do
        present = present_table_names
        missing = required_table_names - present

        {
          enabled: true,
          healthy: healthy?,
          ready: healthy? && missing.empty?,
          database: @config.clickhouse_database,
          required_tables: required_table_names,
          present_tables: present,
          missing_tables: missing
        }
      end
    rescue StandardError => e
      {
        enabled: true,
        healthy: false,
        ready: false,
        database: @config.clickhouse_database,
        required_tables: required_table_names,
        present_tables: [],
        missing_tables: required_table_names,
        error: "#{e.class}: #{e.message}"
      }
    end

    private

    def insert_row!(table_name, attributes)
      return unless enabled?

      query = "INSERT INTO #{full_table_name(table_name)} FORMAT JSONEachRow"
      body = "#{attributes.to_json}\n"

      response = post_query(query, body)
      return if response.is_a?(Net::HTTPSuccess)

      raise Error, "ClickHouse insert failed: #{response.code} #{response.body.to_s.strip}"
    end

    def full_table_name(table_name)
      "#{clickhouse_identifier(@config.clickhouse_database)}.#{clickhouse_identifier(table_name)}"
    end

    def schema_statements(schema_sql)
      schema_sql.to_s.split(/;\s*(?:\n|\z)/).filter_map do |statement|
        stripped = statement.strip
        stripped.presence
      end
    end

    def present_table_names
      rows = select_rows!(<<~SQL.squish)
        SELECT name
        FROM system.tables
        WHERE database = #{quote_clickhouse_string(@config.clickhouse_database)}
          AND name IN (#{required_table_names.map { |name| quote_clickhouse_string(name) }.join(", ")})
        ORDER BY name
      SQL

      rows.map { |row| row.fetch("name").to_s }.sort
    end

    def required_table_names
      REQUIRED_TABLES.map do |table_name|
        case table_name
        when "events_raw"
          @config.clickhouse_events_table
        when "spans_raw"
          @config.clickhouse_spans_table
        else
          table_name
        end
      end.map(&:to_s).uniq.sort
    end

    def disabled_schema_status
      {
        enabled: false,
        healthy: false,
        ready: false,
        database: @config.clickhouse_database,
        required_tables: required_table_names,
        present_tables: [],
        missing_tables: []
      }
    end

    def quote_clickhouse_string(value)
      escaped = value.to_s.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }
      "'#{escaped}'"
    end

    def clickhouse_identifier(value)
      identifier = value.to_s
      return identifier if identifier.match?(IDENTIFIER_PATTERN)

      raise Error, "Unsafe ClickHouse identifier: #{identifier.inspect}"
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

    def parse_json_each_row(body)
      body.to_s.each_line.filter_map do |line|
        stripped = line.strip
        next if stripped.empty?

        JSON.parse(stripped)
      end
    end

    def build_uri(query)
      uri = URI.parse(@config.clickhouse_url)
      unless query_api_mode?(uri)
        params = URI.decode_www_form(uri.query.to_s)
        params << [ "query", query ]
        uri.query = URI.encode_www_form(params)
      end
      uri
    end

    def query_api_mode?(uri = URI.parse(@config.clickhouse_url))
      uri.host == "queries.clickhouse.cloud"
    end

    def health_cache_key
      [ "clickhouse", "health", @config.clickhouse_url, @config.clickhouse_database, @config.clickhouse_events_table, @config.clickhouse_spans_table ]
    end

    def schema_cache_key
      [ "clickhouse", "schema", @config.clickhouse_url, @config.clickhouse_database, required_table_names ]
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

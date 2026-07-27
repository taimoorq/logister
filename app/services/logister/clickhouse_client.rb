require "json"
require "net/http"
require "uri"

module Logister
  class ClickhouseClient
    class Error < StandardError; end
    HEALTH_CACHE_TTL = 30.seconds
    SCHEMA_CACHE_TTL = 30.seconds
    CANONICAL_EVENT_TYPE = "Enum8('error' = 1, 'metric' = 2, 'transaction' = 3, 'log' = 4, 'check_in' = 5)".freeze
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
      write_enabled?
    end

    def write_enabled?
      clickhouse_mode != "disabled"
    end

    def read_enabled?
      clickhouse_mode == "read_preferred"
    end

    def insert_event!(attributes)
      insert_events!([ attributes ])
    end

    def insert_events!(attributes)
      insert_rows!(@config.clickhouse_events_table, attributes)
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
      clear_schema_cache!
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

    def events_table_name
      full_table_name(@config.clickhouse_events_table)
    end

    def spans_table_name
      full_table_name(@config.clickhouse_spans_table)
    end

    def database_name
      clickhouse_identifier(@config.clickhouse_database)
    end

    def events_table
      clickhouse_identifier(@config.clickhouse_events_table)
    end

    def qualified_table_name(table_name)
      full_table_name(table_name)
    end

    def event_type_column_types
      return {} unless enabled?

      rows = select_rows!(<<~SQL.squish)
        SELECT table, type
        FROM system.columns
        WHERE database = #{quote_clickhouse_string(@config.clickhouse_database)}
          AND table IN (#{event_type_object_names.map { |name| quote_clickhouse_string(name) }.join(", ")})
          AND name = 'event_type'
        ORDER BY table
      SQL

      rows.to_h { |row| [ row.fetch("table").to_s, row.fetch("type").to_s ] }
    end

    def clear_schema_cache!
      Rails.cache.delete(schema_cache_key)
    end

    def schema_status
      return disabled_schema_status unless enabled?

      Rails.cache.fetch(schema_cache_key, expires_in: SCHEMA_CACHE_TTL) do
        present = present_table_names
        missing = required_table_names - present
        event_type_columns = event_type_column_types
        schema_issues = event_type_schema_issues(present, event_type_columns)
        healthy = healthy?

        {
          enabled: true,
          healthy: healthy,
          ready: healthy && missing.empty? && schema_issues.empty?,
          database: @config.clickhouse_database,
          required_tables: required_table_names,
          present_tables: present,
          missing_tables: missing,
          event_type_columns: event_type_columns,
          schema_issues: schema_issues
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
        event_type_columns: {},
        schema_issues: [],
        error: "#{e.class}: #{e.message}"
      }
    end

    private

    def clickhouse_mode
      configured_mode = @config.clickhouse_mode if @config.respond_to?(:clickhouse_mode)
      return configured_mode.to_s if configured_mode.present?

      @config.clickhouse_enabled ? "dual_write" : "disabled"
    end

    def insert_row!(table_name, attributes)
      insert_rows!(table_name, [ attributes ])
    end

    def insert_rows!(table_name, rows)
      return unless enabled?
      return if rows.blank?

      query = "INSERT INTO #{full_table_name(table_name)} FORMAT JSONEachRow"
      body = "#{rows.map(&:to_json).join("\n")}\n"

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

    def event_type_object_names
      [ @config.clickhouse_events_table, "events_1m", "mv_events_1m" ].map(&:to_s).uniq.sort
    end

    def event_type_schema_issues(present_table_names, column_types)
      (event_type_object_names & present_table_names).filter_map do |table_name|
        actual_type = column_types[table_name]
        next if actual_type == CANONICAL_EVENT_TYPE

        if actual_type.present?
          "#{table_name}.event_type uses #{actual_type}; expected #{CANONICAL_EVENT_TYPE}"
        else
          "#{table_name}.event_type is missing"
        end
      end
    end

    def disabled_schema_status
      {
        enabled: false,
        healthy: false,
        ready: false,
        database: @config.clickhouse_database,
        required_tables: required_table_names,
        present_tables: [],
        missing_tables: [],
        event_type_columns: {},
        schema_issues: []
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
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, URI::InvalidURIError => e
      raise Error, "ClickHouse request failed: #{e.class}: #{e.message}"
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

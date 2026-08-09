require "json"
require "net/http"
require "stringio"
require "uri"
require "zlib"

module Logister
  class ClickhouseClient
    class Error < StandardError
      def retryable? = true
    end
    class ResponseError < Error
      attr_reader :status_code

      def initialize(message, status_code:)
        @status_code = status_code.to_i
        super(message)
      end

      def retryable?
        status_code >= 500 || status_code.in?([ 408, 429 ])
      end
    end
    class CircuitOpen < Error; end
    HEALTH_CACHE_TTL = 30.seconds
    SCHEMA_CACHE_TTL = 30.seconds
    CANONICAL_EVENT_TYPE = "Enum8('error' = 1, 'metric' = 2, 'transaction' = 3, 'log' = 4, 'check_in' = 5)".freeze
    IDENTIFIER_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/
    SCHEMA_VERSION = 2
    REQUIRED_TABLES = %w[
      events_raw
      spans_raw
      event_facts_v2
      span_facts_v2
      event_facts_1m_v2
      event_facts_1h_v2
      metric_facts_1m_v2
      metric_facts_1h_v2
      transaction_facts_1m_v2
      transaction_facts_1h_v2
      error_occurrences_1h_v2
      log_events_1h_v2
      check_in_observations_1h_v2
      request_span_facts_1m_v2
      request_span_facts_1h_v2
    ].freeze
    REQUIRED_RAW_COLUMNS = {
      "events_raw" => {
        "projection_version" => "UInt64",
        "identity_checksum" => "UInt128",
        "metric_value" => "Nullable(Float64)",
        "duration_ms" => "Nullable(Float64)",
        "transaction_status" => "LowCardinality(String)",
        "log_severity" => "LowCardinality(String)",
        "error_fingerprint" => "String",
        "check_in_slug" => "String",
        "check_in_status" => "LowCardinality(String)",
        "context_json" => "String",
        "tags" => "Map(String, String)"
      },
      "spans_raw" => {
        "projection_version" => "UInt64",
        "identity_checksum" => "UInt128",
        "duration_ms" => "Float64",
        "http_method" => "LowCardinality(String)",
        "http_status_code" => "Nullable(UInt16)",
        "is_root" => "UInt8",
        "context_json" => "String",
        "tags" => "Map(String, String)"
      }
    }.freeze

    def initialize(config: Rails.configuration.x.logister, circuit_breaker: nil, force_enabled: false)
      @config = config
      @force_enabled = force_enabled
      @circuit_breaker = circuit_breaker || ClickhouseCircuitBreaker.new(config: config)
      @http_connections = {}
      @connection_mutex = Mutex.new
      TelemetryStoreGeneration.register_clickhouse_once!(config) unless force_enabled || Rails.env.test?
    end

    def enabled?
      write_enabled?
    end

    def write_enabled?
      @force_enabled || clickhouse_mode != "disabled"
    end

    def read_enabled?
      @force_enabled || clickhouse_mode == "read_preferred"
    end

    def insert_event!(attributes, deduplication_token: nil, gzip: false)
      insert_events!([ attributes ], deduplication_token: deduplication_token, gzip: gzip)
    end

    def insert_events!(attributes, deduplication_token: nil, gzip: false)
      insert_rows!(
        @config.clickhouse_events_table,
        attributes,
        deduplication_token: deduplication_token,
        gzip: gzip
      )
    end

    def insert_span!(attributes, deduplication_token: nil, gzip: false)
      insert_spans!([ attributes ], deduplication_token: deduplication_token, gzip: gzip)
    end

    def insert_spans!(attributes, deduplication_token: nil, gzip: false)
      insert_rows!(
        @config.clickhouse_spans_table,
        attributes,
        deduplication_token: deduplication_token,
        gzip: gzip
      )
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

    def event_facts_table_name
      qualified_table_name("event_facts_v2")
    end

    def span_facts_table_name
      qualified_table_name("span_facts_v2")
    end

    def database_name
      clickhouse_identifier(@config.clickhouse_database)
    end

    def events_table
      clickhouse_identifier(@config.clickhouse_events_table)
    end

    def spans_table
      clickhouse_identifier(@config.clickhouse_spans_table)
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
        object_engines = object_metadata
        present = object_engines.keys.sort
        missing = required_table_names - present
        event_type_columns = event_type_column_types
        raw_columns = required_raw_column_types
        schema_issues = event_type_schema_issues(present, event_type_columns) +
          raw_column_schema_issues(raw_columns) + object_engine_schema_issues(object_engines)
        healthy = healthy?

        {
          schema_version: SCHEMA_VERSION,
          enabled: true,
          healthy: healthy,
          ready: healthy && missing.empty? && schema_issues.empty?,
          database: @config.clickhouse_database,
          required_tables: required_table_names,
          present_tables: present,
          missing_tables: missing,
          object_engines: object_engines,
          raw_columns: raw_columns,
          event_type_columns: event_type_columns,
          schema_issues: schema_issues,
          duplicate_safety: "logical_fact_views"
        }
      end
    rescue StandardError => e
      {
        schema_version: SCHEMA_VERSION,
        enabled: true,
        healthy: false,
        ready: false,
        database: @config.clickhouse_database,
        required_tables: required_table_names,
        present_tables: [],
        missing_tables: required_table_names,
        object_engines: {},
        raw_columns: {},
        event_type_columns: {},
        schema_issues: [],
        error: "#{e.class}: #{e.message}"
      }
    end

    def circuit_breaker_status
      @circuit_breaker.status
    end

    def close
      @connection_mutex.synchronize do
        @http_connections.each_value { |http| http.finish if http.active? }
        @http_connections.clear
      end
    end

    private

    def clickhouse_mode
      configured_mode = @config.clickhouse_mode if @config.respond_to?(:clickhouse_mode)
      return configured_mode.to_s if configured_mode.present?

      @config.clickhouse_enabled ? "dual_write" : "disabled"
    end

    def insert_rows!(table_name, rows, deduplication_token: nil, gzip: false)
      return unless enabled?
      return if rows.blank?

      query = "INSERT INTO #{full_table_name(table_name)} FORMAT JSONEachRow"
      body = "#{rows.map(&:to_json).join("\n")}\n"

      options = {}
      options[:deduplication_token] = deduplication_token if deduplication_token.present?
      options[:gzip] = true if gzip
      response = options.empty? ? post_query(query, body) : post_query(query, body, **options)
      return if response.is_a?(Net::HTTPSuccess)

      raise ResponseError.new(
        "ClickHouse insert failed: #{response.code} #{response.body.to_s.strip}",
        status_code: response.code
      )
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

    def object_metadata
      rows = select_rows!(<<~SQL.squish)
        SELECT name, engine
        FROM system.tables
        WHERE database = #{quote_clickhouse_string(@config.clickhouse_database)}
          AND name IN (#{required_table_names.map { |name| quote_clickhouse_string(name) }.join(", ")})
        ORDER BY name
      SQL

      rows.to_h { |row| [ row.fetch("name").to_s, row.fetch("engine", "").to_s ] }
    end

    def required_raw_column_types
      raw_table_names = [ @config.clickhouse_events_table, @config.clickhouse_spans_table ].map(&:to_s)
      rows = select_rows!(<<~SQL.squish)
        SELECT table, name, type
        FROM system.columns
        WHERE database = #{quote_clickhouse_string(@config.clickhouse_database)}
          AND table IN (#{raw_table_names.map { |name| quote_clickhouse_string(name) }.join(", ")})
          AND name IN (#{required_raw_column_names.map { |name| quote_clickhouse_string(name) }.join(", ")})
        ORDER BY table, name
      SQL

      rows.each_with_object({}) do |row, columns|
        columns[row.fetch("table").to_s] ||= {}
        columns[row.fetch("table").to_s][row.fetch("name").to_s] = row.fetch("type").to_s
      end
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
      [ @config.clickhouse_events_table, "event_facts_v2", "event_facts_1m_v2", "event_facts_1h_v2" ].map(&:to_s).uniq.sort
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

    def required_raw_column_names
      REQUIRED_RAW_COLUMNS.values.flat_map(&:keys).uniq.sort
    end

    def raw_column_schema_issues(column_types)
      REQUIRED_RAW_COLUMNS.flat_map do |generic_table_name, expected_columns|
        table_name = generic_table_name == "events_raw" ? @config.clickhouse_events_table.to_s : @config.clickhouse_spans_table.to_s
        actual_columns = column_types.fetch(table_name, {})
        expected_columns.filter_map do |column_name, expected_type|
          actual_type = actual_columns[column_name]
          if actual_type.blank?
            "#{table_name}.#{column_name} is missing"
          elsif actual_type != expected_type
            "#{table_name}.#{column_name} uses #{actual_type}; expected #{expected_type}"
          end
        end
      end
    end

    def object_engine_schema_issues(metadata)
      required_table_names.filter_map do |table_name|
        engine = metadata[table_name]
        next if engine.blank?

        raw_table = table_name.in?([ @config.clickhouse_events_table.to_s, @config.clickhouse_spans_table.to_s ])
        valid = raw_table ? engine.end_with?("MergeTree") : engine == "View"
        next if valid

        expected = raw_table ? "a MergeTree-family engine" : "View"
        "#{table_name} uses #{engine}; expected #{expected}"
      end
    end

    def disabled_schema_status
      {
        schema_version: SCHEMA_VERSION,
        enabled: false,
        healthy: false,
        ready: false,
        database: @config.clickhouse_database,
        required_tables: required_table_names,
        present_tables: [],
        missing_tables: [],
        object_engines: {},
        raw_columns: {},
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

    def post_query(query, body, deduplication_token: nil, gzip: false)
      unless @circuit_breaker.allow_request?
        raise CircuitOpen, "ClickHouse request skipped: circuit breaker is open"
      end

      settings = {}
      settings["max_execution_time"] = ENV.fetch("LOGISTER_CLICKHOUSE_MAX_EXECUTION_SECONDS", "30")
      settings["insert_deduplication_token"] = deduplication_token if deduplication_token.present?
      settings["insert_deduplicate"] = "1" if deduplication_token.present?
      settings["deduplicate_blocks_in_dependent_materialized_views"] = "1" if deduplication_token.present?
      uri = build_uri(query, settings: settings)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = query_api_mode?(uri) ? "application/json" : "application/x-ndjson"
      request["Connection"] = "keep-alive"
      request.basic_auth(@config.clickhouse_username, @config.clickhouse_password) if @config.clickhouse_username.present?
      payload = request_body(query, body)
      if gzip && payload.present?
        payload = gzip_payload(payload)
        request["Content-Encoding"] = "gzip"
      end
      request.body = payload

      response = with_http_connection(uri) do |http|
        http.request(request)
      end
      if transient_response?(response)
        @circuit_breaker.record_failure!(error: Error.new("ClickHouse response failed: HTTP #{response.code}"))
      else
        @circuit_breaker.record_success!
      end
      response
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, URI::InvalidURIError => e
      @circuit_breaker.record_failure!(error: e)
      raise Error, "ClickHouse request failed: #{e.class}: #{e.message}"
    end

    def transient_response?(response)
      code = response.code.to_i
      code >= 500 || code == 408 || code == 429
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

    def build_uri(query, settings: {})
      uri = URI.parse(@config.clickhouse_url)
      params = URI.decode_www_form(uri.query.to_s)
      unless query_api_mode?(uri)
        params << [ "query", query ]
      end
      settings.each { |name, value| params << [ name.to_s, value.to_s ] }
      uri.query = URI.encode_www_form(params) if params.any?
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
      @connection_mutex.synchronize do
        key = [ uri.scheme, uri.host, uri.port ]
        http = @http_connections[key]
        unless http&.active?
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 2
          http.read_timeout = 5
          http.keep_alive_timeout = 30
          http.start
          @http_connections[key] = http
        end
        yield http
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
        @http_connections.delete(key)&.finish rescue nil
        raise
      end
    end

    def gzip_payload(payload)
      output = StringIO.new("".b)
      Zlib::GzipWriter.wrap(output) { |writer| writer.write(payload) }
      output.string
    end
  end
end

# frozen_string_literal: true

module Logister
  class ClickhouseSchemaRepairer
    EVENTS_TABLE_PLACEHOLDER = "__LOGISTER_EVENTS_TABLE__"
    SPANS_TABLE_PLACEHOLDER = "__LOGISTER_SPANS_TABLE__"
    NON_REPLICATED_DEDUPLICATION_WINDOW = 10_000

    def self.call(...)
      new(...).call
    end

    def initialize(client: nil, schema_sql: nil)
      @client = client || ClickhouseClient.new(config: migration_config)
      @owns_client = client.nil?
      @schema_sql = schema_sql || Rails.root.join("docs/clickhouse_schema.sql").read
    end

    def call
      return disabled_result unless client.enabled?

      loaded_statements = client.load_schema!(rendered_schema_sql)
      column_types = client.event_type_column_types
      repaired_columns = repair_event_type_columns(column_types)
      deduplication_tables = enforce_insert_deduplication!

      client.clear_schema_cache!
      status = client.schema_status
      unless status.fetch(:ready)
        issues = Array(status[:schema_issues]) + Array(status[:missing_tables]).map { |name| "missing #{name}" }
        raise ClickhouseClient::Error, "ClickHouse schema repair incomplete: #{issues.join('; ')}"
      end

      {
        enabled: true,
        loaded_statements: loaded_statements,
        repaired_columns: repaired_columns,
        rebuilt_views: [],
        deduplication_tables: deduplication_tables,
        schema: status
      }
    ensure
      client.close if @owns_client
    end

    private

    attr_reader :client, :schema_sql

    def migration_config
      runtime = Rails.configuration.x.logister
      ActiveSupport::OrderedOptions.new.tap do |config|
        config.clickhouse_mode = runtime.clickhouse_mode
        config.clickhouse_enabled = runtime.clickhouse_enabled
        config.clickhouse_url = runtime.clickhouse_url
        config.clickhouse_database = runtime.clickhouse_database
        config.clickhouse_events_table = runtime.clickhouse_events_table
        config.clickhouse_spans_table = runtime.clickhouse_spans_table
        config.clickhouse_username = InstanceConfiguration.value("clickhouse.migration_username").presence || runtime.clickhouse_username
        config.clickhouse_password = InstanceConfiguration.value("clickhouse.migration_password").presence || runtime.clickhouse_password
      end
    end

    def rendered_schema_sql
      rendered = schema_sql.dup
      rendered.gsub!("logister.events_raw", EVENTS_TABLE_PLACEHOLDER)
      rendered.gsub!("logister.spans_raw", SPANS_TABLE_PLACEHOLDER)
      rendered.gsub!("CREATE DATABASE IF NOT EXISTS logister", "CREATE DATABASE IF NOT EXISTS #{client.database_name}")
      rendered.gsub!(/\blogister\.([A-Za-z_][A-Za-z0-9_]*)/) do
        client.qualified_table_name(Regexp.last_match(1))
      end
      rendered.gsub!(EVENTS_TABLE_PLACEHOLDER, client.events_table_name)
      rendered.gsub!(SPANS_TABLE_PLACEHOLDER, client.spans_table_name)
      rendered
    end

    def repair_event_type_columns(column_types)
      actual_type = column_types[client.events_table]
      return [] if actual_type.blank? || actual_type == ClickhouseClient::CANONICAL_EVENT_TYPE

      client.execute!(<<~SQL.squish)
        ALTER TABLE #{client.events_table_name}
        MODIFY COLUMN event_type #{ClickhouseClient::CANONICAL_EVENT_TYPE}
      SQL
      [ client.events_table ]
    end

    def enforce_insert_deduplication!
      table_names = [ client.events_table_name, client.spans_table_name ]
      table_names.each do |table_name|
        client.execute!(<<~SQL.squish)
          ALTER TABLE #{table_name}
          MODIFY SETTING non_replicated_deduplication_window = #{NON_REPLICATED_DEDUPLICATION_WINDOW}
        SQL
      end
      table_names
    end

    def disabled_result
      {
        enabled: false,
        loaded_statements: 0,
        repaired_columns: [],
        rebuilt_views: [],
        deduplication_tables: [],
        schema: client.schema_status
      }
    end
  end
end

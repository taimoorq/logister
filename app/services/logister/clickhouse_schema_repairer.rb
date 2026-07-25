# frozen_string_literal: true

module Logister
  class ClickhouseSchemaRepairer
    EVENT_ROLLUP_TABLE = "events_1m"
    EVENT_ROLLUP_VIEW = "mv_events_1m"
    EVENTS_TABLE_PLACEHOLDER = "__LOGISTER_EVENTS_TABLE__"
    SPANS_TABLE_PLACEHOLDER = "__LOGISTER_SPANS_TABLE__"

    def self.call(...)
      new(...).call
    end

    def initialize(client: nil, schema_sql: nil)
      @client = client || ClickhouseClient.new(config: migration_config)
      @schema_sql = schema_sql || Rails.root.join("docs/clickhouse_schema.sql").read
    end

    def call
      return disabled_result unless client.enabled?

      loaded_statements = client.load_schema!(rendered_schema_sql)
      column_types = client.event_type_column_types
      repaired_columns = repair_event_type_columns(column_types)
      rebuilt_views = rebuild_event_rollup_view_if_needed(column_types, repaired_columns)

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
        rebuilt_views: rebuilt_views,
        schema: status
      }
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
      repairable_tables.filter_map do |table_name, qualified_table_name|
        actual_type = column_types[table_name]
        next if actual_type.blank? || actual_type == ClickhouseClient::CANONICAL_EVENT_TYPE

        client.execute!(<<~SQL.squish)
          ALTER TABLE #{qualified_table_name}
          MODIFY COLUMN event_type #{ClickhouseClient::CANONICAL_EVENT_TYPE}
        SQL
        table_name
      end
    end

    def rebuild_event_rollup_view_if_needed(column_types, repaired_columns)
      view_type = column_types[EVENT_ROLLUP_VIEW]
      return [] if repaired_columns.empty? && view_type == ClickhouseClient::CANONICAL_EVENT_TYPE

      client.execute!("DROP VIEW IF EXISTS #{client.qualified_table_name(EVENT_ROLLUP_VIEW)}")
      client.execute!(event_rollup_view_sql)
      [ EVENT_ROLLUP_VIEW ]
    end

    def repairable_tables
      {
        client.events_table => client.events_table_name,
        EVENT_ROLLUP_TABLE => client.qualified_table_name(EVENT_ROLLUP_TABLE)
      }
    end

    def event_rollup_view_sql
      <<~SQL.squish
        CREATE MATERIALIZED VIEW #{client.qualified_table_name(EVENT_ROLLUP_VIEW)}
        TO #{client.qualified_table_name(EVENT_ROLLUP_TABLE)}
        AS
        SELECT
          toStartOfMinute(occurred_at) AS bucket,
          project_id,
          event_type,
          level,
          sumState(toUInt64(1)) AS count
        FROM #{client.events_table_name}
        GROUP BY bucket, project_id, event_type, level
      SQL
    end

    def disabled_result
      {
        enabled: false,
        loaded_statements: 0,
        repaired_columns: [],
        rebuilt_views: [],
        schema: client.schema_status
      }
    end
  end
end

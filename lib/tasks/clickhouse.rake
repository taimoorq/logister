# frozen_string_literal: true

require "json"

namespace :logister do
  namespace :clickhouse do
    namespace :schema do
      desc "Print ClickHouse schema readiness for Logister analytics tables"
      task status: :environment do
        puts JSON.pretty_generate(Logister::ClickhouseClient.new.schema_status)
      end

      desc "Load the idempotent Logister ClickHouse schema from docs/clickhouse_schema.sql"
      task load: :environment do
        client = Logister::ClickhouseClient.new
        schema_path = Rails.root.join("docs/clickhouse_schema.sql")
        loaded = client.load_schema!(schema_path.read)

        puts JSON.pretty_generate(
          loaded_statements: loaded,
          schema: client.schema_status
        )
      end
    end
  end
end

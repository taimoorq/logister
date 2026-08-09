# frozen_string_literal: true

require "json"

module Logister
  module ProjectPurgeAdapters
    class Clickhouse
      DEFAULT_ROLLUP_TABLES = %w[events_1m request_spans_1m].freeze
      DEFAULT_WRITE_QUIESCENCE = 2.minutes
      DEFAULT_FINAL_VERIFICATION_DELAY = 30.seconds

      def initialize(project_purge:, client: nil, enabled: nil, now: Time.current)
        @project_purge = project_purge
        @injected_client = client
        @owned_clients = []
        @now = now
        @automatic_enabled = if enabled.nil?
          ActiveModel::Type::Boolean.new.cast(ENV.fetch("LOGISTER_ENABLE_PROJECT_PURGE_CLICKHOUSE", "false"))
        else
          enabled
        end
      end

      def call
        snapshot = @project_purge.configuration_snapshot.fetch("clickhouse", {})
        generations = Array(snapshot["generations"])
        if generations.empty?
          return {
            status: "skipped",
            configured: false,
            attested_never_used: true,
            verified_absent: true
          } if snapshot["never_used"] == true

          return awaiting_external(
            "No complete ClickHouse store-generation inventory is recorded; disabled mode is not proof that historical data is absent"
          )
        end
        unless snapshot["generation_inventory_complete"] == true
          return awaiting_external(
            "Attest that the store-generation registry includes every current and historical ClickHouse cluster"
          )
        end
        return awaiting_external("Set LOGISTER_ENABLE_PROJECT_PURGE_CLICKHOUSE=true after rollout validation") unless @automatic_enabled

        quiet_at = write_quiet_at
        if quiet_at && @now < quiet_at
          return awaiting_external(
            "Waiting for ambiguous pre-tombstone remote writes to quiesce",
            retry_at: quiet_at,
            phase: "write_quiescence"
          )
        end

        results = generations.map { |locator| purge_generation!(locator.stringify_keys) }
        if durable_step? && !final_verification_pass?
          verify_at = @now + final_verification_delay
          return awaiting_external(
            "Initial mutation completed; a delayed second mutation and zero-row verification is required",
            retry_at: verify_at,
            phase: "mutation_complete",
            generations: results
          )
        end

        {
          status: "completed",
          configured: true,
          generations: results,
          generation_count: results.size,
          repeated_verification: durable_step?,
          verified_absent: true
        }
      rescue Logister::ClickhouseClient::Error, SocketError, SystemCallError, Timeout::Error => error
        awaiting_external(
          "A recorded ClickHouse generation is unreachable: #{error.class}: #{error.message}",
          phase: "generation_unreachable"
        )
      rescue ArgumentError, KeyError => error
        awaiting_external(
          "A recorded ClickHouse generation cannot be resolved safely: #{error.message}",
          phase: "generation_configuration_invalid"
        )
      ensure
        @owned_clients.each(&:close)
      end

      private

      def purge_generation!(locator)
        client = client_for(locator)
        present_tables = present_target_tables(client)
        mutations = present_tables.map do |table|
          client.execute!(
            "ALTER TABLE #{client.qualified_table_name(table)} DELETE " \
            "WHERE project_id = #{@project_purge.source_project_id.to_i} " \
            "SETTINGS mutations_sync = 2, max_execution_time = 30"
          )
          table
        end
        remaining = remaining_counts(client, present_tables)
        unless remaining.values.all?(&:zero?)
          raise "ClickHouse project rows remain after mutation for generation #{locator['generation_id']}: #{remaining.inspect}"
        end

        {
          generation_id: locator.fetch("generation_id"),
          database: locator.fetch("database"),
          mutated_tables: mutations,
          missing_tables: target_tables(client) - present_tables,
          remaining_rows: remaining,
          verified_absent: true
        }
      end

      def client_for(locator)
        return @injected_client if @injected_client

        config = Rails.configuration.x.logister.dup
        config.clickhouse_mode = "dual_write"
        config.clickhouse_url = locator.fetch("url")
        config.clickhouse_database = locator.fetch("database")
        config.clickhouse_events_table = locator.fetch("events_table")
        config.clickhouse_spans_table = locator.fetch("spans_table")
        credentials = credentials_for(locator.fetch("generation_id"))
        config.clickhouse_username = credentials.fetch("username", locator["username"]).presence
        config.clickhouse_password = credentials.fetch("password", config.clickhouse_password)
        Logister::ClickhouseClient.new(config: config, force_enabled: true).tap { |client| @owned_clients << client }
      end

      def credentials_for(generation_id)
        raw = ENV["LOGISTER_PROJECT_PURGE_CLICKHOUSE_CREDENTIALS_JSON"]
        return {} if raw.blank?

        parsed = JSON.parse(raw)
        value = parsed.fetch(generation_id, {})
        raise ArgumentError, "ClickHouse purge credentials must be an object keyed by generation ID" unless value.is_a?(Hash)

        value.stringify_keys.slice("username", "password")
      rescue JSON::ParserError => error
        raise ArgumentError, "Invalid LOGISTER_PROJECT_PURGE_CLICKHOUSE_CREDENTIALS_JSON: #{error.message}"
      end

      def target_tables(client)
        additional = ENV.fetch("LOGISTER_PROJECT_PURGE_CLICKHOUSE_TABLES", "").split(",").map(&:strip).compact_blank
        [ client.events_table, client.spans_table, *DEFAULT_ROLLUP_TABLES, *additional ].map(&:to_s).uniq
      end

      def present_target_tables(client)
        rows = client.select_rows!(<<~SQL.squish)
          SELECT name
          FROM system.tables
          WHERE database = '#{client.database_name}'
            AND (
              name IN (#{target_tables(client).map { |table| quote(table) }.join(', ')})
              OR (
                engine LIKE '%MergeTree'
                AND name IN (
                  SELECT table
                  FROM system.columns
                  WHERE database = '#{client.database_name}' AND name = 'project_id'
                )
              )
            )
        SQL
        rows.map { |row| row.fetch("name").to_s }
      end

      def remaining_counts(client, tables)
        tables.to_h do |table|
          rows = client.select_rows!(
            "SELECT count() AS count FROM #{client.qualified_table_name(table)} " \
            "WHERE project_id = #{@project_purge.source_project_id.to_i}"
          )
          [ table, rows.first&.fetch("count", 0).to_i ]
        end
      end

      def write_quiet_at
        return unless @project_purge.respond_to?(:tombstoned_at) && @project_purge.tombstoned_at

        @project_purge.tombstoned_at + write_quiescence
      end

      def write_quiescence
        ENV.fetch("LOGISTER_PROJECT_PURGE_WRITE_QUIESCENCE_SECONDS", DEFAULT_WRITE_QUIESCENCE.to_i).to_i.seconds
      end

      def final_verification_delay
        ENV.fetch(
          "LOGISTER_PROJECT_PURGE_FINAL_VERIFICATION_SECONDS",
          DEFAULT_FINAL_VERIFICATION_DELAY.to_i
        ).to_i.seconds
      end

      def durable_step?
        @project_purge.respond_to?(:steps)
      end

      def final_verification_pass?
        return false unless durable_step?

        @project_purge.steps.find_by(store_name: "clickhouse")&.result&.fetch("phase", nil) == "mutation_complete"
      end

      def awaiting_external(reason, retry_at: nil, **details)
        {
          status: "awaiting_external",
          configured: true,
          reason: reason,
          retry_at: retry_at&.utc&.iso8601,
          rollout_gate: "LOGISTER_ENABLE_PROJECT_PURGE_CLICKHOUSE",
          inventory_gate: "LOGISTER_ATTEST_CLICKHOUSE_GENERATION_INVENTORY_COMPLETE",
          project_id: @project_purge.source_project_id,
          verified_absent: false
        }.merge(details).compact
      end

      def quote(value)
        "'#{value.to_s.gsub("\\", "\\\\").gsub("'", "\\\\'")}'"
      end
    end
  end
end

# frozen_string_literal: true

clickhouse_config = Rails.application.config.x.logister
clickhouse_config.clickhouse_mode = InstanceConfiguration.value("clickhouse.mode")
clickhouse_config.clickhouse_enabled = clickhouse_config.clickhouse_mode != "disabled"
clickhouse_config.clickhouse_url = InstanceConfiguration.value("clickhouse.url")
clickhouse_config.clickhouse_database = InstanceConfiguration.value("clickhouse.database")
clickhouse_config.clickhouse_events_table = InstanceConfiguration.value("clickhouse.events_table")
clickhouse_config.clickhouse_spans_table = InstanceConfiguration.value("clickhouse.spans_table")
clickhouse_config.clickhouse_username = InstanceConfiguration.value("clickhouse.username").presence
clickhouse_config.clickhouse_password = InstanceConfiguration.value("clickhouse.password").to_s
clickhouse_config.clickhouse_circuit_failure_threshold = InstanceConfiguration.value("clickhouse.circuit_failure_threshold")
clickhouse_config.clickhouse_circuit_open_seconds = InstanceConfiguration.value("clickhouse.circuit_open_seconds")

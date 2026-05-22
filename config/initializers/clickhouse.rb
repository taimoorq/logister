# frozen_string_literal: true

clickhouse_config = Rails.application.config.x.logister
boolean = ActiveModel::Type::Boolean.new

clickhouse_config.clickhouse_enabled = boolean.cast(ENV.fetch("LOGISTER_CLICKHOUSE_ENABLED", "false"))
clickhouse_config.clickhouse_url = ENV.fetch("LOGISTER_CLICKHOUSE_URL", "http://127.0.0.1:8123")
clickhouse_config.clickhouse_database = ENV.fetch("LOGISTER_CLICKHOUSE_DATABASE", "logister")
clickhouse_config.clickhouse_events_table = ENV.fetch("LOGISTER_CLICKHOUSE_EVENTS_TABLE", "events_raw")
clickhouse_config.clickhouse_username = ENV["LOGISTER_CLICKHOUSE_USERNAME"].to_s.presence
clickhouse_config.clickhouse_password = ENV["LOGISTER_CLICKHOUSE_PASSWORD"].to_s

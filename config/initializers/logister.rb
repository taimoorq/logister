Rails.application.configure do
  config.x.logister.clickhouse_enabled = ENV.fetch("LOGISTER_CLICKHOUSE_ENABLED", "false") == "true"
  config.x.logister.clickhouse_url = ENV.fetch("LOGISTER_CLICKHOUSE_URL", "http://127.0.0.1:8123")
  config.x.logister.clickhouse_database = ENV.fetch("LOGISTER_CLICKHOUSE_DATABASE", "logister")
  config.x.logister.clickhouse_events_table = ENV.fetch("LOGISTER_CLICKHOUSE_EVENTS_TABLE", "events_raw")
  config.x.logister.clickhouse_username = ENV["LOGISTER_CLICKHOUSE_USERNAME"]
  config.x.logister.clickhouse_password = ENV["LOGISTER_CLICKHOUSE_PASSWORD"]
  config.x.logister.redis_url = ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")
end

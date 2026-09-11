# frozen_string_literal: true

require_relative "../../config/environment"

abort "Recovery harness requires test mode" unless Rails.env.test?
TelemetryProjectorJob.queue_adapter = :sidekiq
configuration = Rails.configuration.x.logister
configuration.clickhouse_mode = "dual_write"
configuration.clickhouse_enabled = true
configuration.clickhouse_url = ENV.fetch("RECOVERY_CLICKHOUSE_URL")
configuration.clickhouse_database = ENV.fetch("RECOVERY_CLICKHOUSE_DATABASE")
configuration.clickhouse_events_table = "events_raw"
configuration.clickhouse_spans_table = "spans_raw"
configuration.clickhouse_username = "logister_test"
configuration.clickhouse_password = "test-only"

module TelemetryRecoveryFault
  def insert_event_payload!(...)
    super.tap do
      if ENV["RECOVERY_STOP_AFTER_INSERT"] == "true"
        Sidekiq.redis { |redis| redis.set("recovery:external_insert_committed", "1") }
        Process.kill("STOP", Process.pid)
      end
    end
  end
end
Logister::ClickhouseClient.prepend(TelemetryRecoveryFault)

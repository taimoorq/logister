# frozen_string_literal: true

require "rails_helper"
require "ostruct"
require "sidekiq/redis_connection"
require "socket"
require "tmpdir"

RSpec.describe "Telemetry crash recovery against real stores", type: :model do
  self.use_transactional_tests = false

  it "recovers a killed worker after external success, preserving exact bytes, logical facts and PG progress" do
    url = ENV["RECOVERY_CLICKHOUSE_URL"]
    skip "Set RECOVERY_CLICKHOUSE_URL to an isolated local ClickHouse test server" if url.blank?
    raise "Recovery ClickHouse must be local" unless URI(url).host.in?(%w[localhost 127.0.0.1 ::1])

    Dir.mktmpdir("logister-telemetry-recovery") do |directory|
      database = "recovery_#{SecureRandom.hex(8)}"
      config = OpenStruct.new(clickhouse_mode: "dual_write", clickhouse_url: url, clickhouse_database: database,
        clickhouse_events_table: "events_raw", clickhouse_spans_table: "spans_raw",
        clickhouse_username: "logister_test", clickhouse_password: "test-only")
      client = Logister::ClickhouseClient.new(config: config, force_enabled: true)
      schema = Rails.root.join("docs/clickhouse_schema.sql").read.gsub(/\blogister\b/, database)
      client.load_schema!(schema)
      project = create(:project, user: users(:one))
      api_key = create(:api_key, project: project, user: project.user)
      recorded_at = Time.current
      deliveries = 2.times.map do
        accepted = IngestEventPersistence.new(project: project, api_key: api_key,
          attributes: { uuid: SecureRandom.uuid, event_type: "log", message: "recovery café 世界", occurred_at: recorded_at },
          clickhouse_writable: true, installation: nil).call
        accepted.outbox_event.telemetry_deliveries.find_by!(destination: "clickhouse_event")
      end

      socket = TCPServer.new("127.0.0.1", 0)
      port = socket.addr[1]
      socket.close
      log = File.join(directory, "processes.log")
      redis_pid = Process.spawn("redis-server", "--bind", "127.0.0.1", "--port", port.to_s,
        "--save", "", "--appendonly", "no", out: log, err: [ :child, :out ])
      redis_url = "redis://127.0.0.1:#{port}/0"
      redis = Redis.new(url: redis_url, connect_timeout: 1, read_timeout: 1)
      await_condition(log) { redis.ping == "PONG" rescue false }
      pool = Sidekiq::RedisConnection.create(url: redis_url, size: 1)
      allow(Sidekiq).to receive(:redis).and_yield(redis)
      previous_adapter = TelemetryProjectorJob.queue_adapter
      TelemetryProjectorJob.queue_adapter = :sidekiq
      environment = {
        "RAILS_ENV" => "test", "SIDEKIQ_CONCURRENCY" => "5", "SIDEKIQ_PROJECTOR_CONCURRENCY" => "3",
        "REDIS_URL" => redis_url, "REDIS_SIDEKIQ_URL" => redis_url, "REDIS_CACHE_URL" => redis_url, "REDIS_RATE_LIMIT_URL" => redis_url,
        "RECOVERY_CLICKHOUSE_URL" => url, "RECOVERY_CLICKHOUSE_DATABASE" => database,
        "LOGISTER_BATCHED_PROJECTION" => "true", "LOGISTER_BOUNDED_PROJECTOR" => "true",
        "LOGISTER_ORDERED_DELIVERY_CLAIMS" => "true", "RECOVERY_STOP_AFTER_INSERT" => "true"
      }
      worker_pid = start_worker(environment, log)
      admission = Logister::TelemetryProjectorAdmission.new
      Sidekiq::Client.via(pool) { admission.wake }
      await_condition(log) { redis.get("recovery:external_insert_committed") == "1" }

      batch = TelemetryProjectionBatch.find_by!(project: project)
      original_body = batch.payload
      original_key = batch.batch_key
      expect(batch.delivery_ids).to match_array(deliveries.map(&:id))
      expect(row_count(client, database, "events_raw")).to eq(2)
      watermark = TelemetryProjectionWatermark.find_by!(project: project)
      expect(watermark).to have_attributes(accepted_count: 2, delivered_count: 0)
      expect(deliveries.map(&:reload)).to all(be_processing)

      # Kill the stopped OS process, so neither transaction cleanup nor job
      # ensure callbacks run. Both queue and database recovery are necessary.
      Process.kill("KILL", worker_pid)
      Process.wait(worker_pid)
      worker_pid = nil
      IngestEvent.where(project_id: project.id).update_all(message: "changed after external commit", updated_at: Time.current)
      # Move real lease deadlines past the boundary without a two-minute sleep.
      TelemetryDelivery.where(id: deliveries.map(&:id)).update_all(lease_expires_at: Time.current - 1.second)
      running_key = Logister::TelemetryProjectorAdmission::KEYS[2]
      redis.zrange(running_key, 0, -1).each { |owner| redis.zadd(running_key, 0, owner) }
      redis.del(Logister::TelemetryProjectorAdmission::RECOVERY_KEY)
      worker_pid = start_worker(environment.merge("RECOVERY_STOP_AFTER_INSERT" => "false"), log)
      Sidekiq::Client.via(pool) { admission.recover }
      await_condition(log) { TelemetryDelivery.where(id: deliveries.map(&:id), status: "completed").count == 2 }

      expect(watermark.reload).to have_attributes(accepted_count: 2, delivered_count: 2, terminal_failure_count: 0)
      expect(watermark.accepted_checksum).to eq(watermark.delivered_checksum)
      expect(TelemetryProjectionBatch.where(project: project)).to be_empty
      expect(row_count(client, database, "events_raw")).to eq(2)
      expect(row_count(client, database, "event_facts_v2")).to eq(2)
      expect(client.select_rows!("SELECT DISTINCT message FROM #{database}.event_facts_v2 FORMAT JSONEachRow").sole.fetch("message"))
        .to eq("recovery café 世界")

      # Correct product facts also survive replay outside the provider's finite
      # deduplication window. A new token deliberately bypasses that cache.
      client.insert_event_payload!(original_body, deduplication_token: "#{original_key}-outside-window")
      expect(row_count(client, database, "events_raw")).to eq(4)
      expect(row_count(client, database, "event_facts_v2")).to eq(2)
    ensure
      stop_process(worker_pid)
      TelemetryProjectorJob.queue_adapter = previous_adapter if previous_adapter
      pool&.shutdown(&:close)
      redis&.close
      stop_process(redis_pid)
      if project
        IngestEvent.where(project_id: project.id).delete_all
        ApiKey.where(project_id: project.id).delete_all
        ProjectMembership.where(project_id: project.id).delete_all
        Project.where(id: project.id).delete_all
      end
      client&.execute!("DROP DATABASE IF EXISTS #{database} SYNC") if database
      client&.close
    end
  end

  def row_count(client, database, table)
    client.select_rows!("SELECT count() AS count FROM #{database}.#{table} FORMAT JSONEachRow").sole.fetch("count").to_i
  end

  def start_worker(environment, log)
    Process.spawn(environment, RbConfig.ruby, "-S", "bundle", "exec", "sidekiq",
      "-e", "test", "-C", "config/sidekiq-core.yml", "-r", "./spec/fixtures/telemetry_recovery_boot.rb",
      "-t", "2", chdir: Rails.root.to_s, out: [ log, "a" ], err: [ :child, :out ])
  end

  def await_condition(log, seconds: 30)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until yield
      raise "Recovery probe timed out:\n#{File.read(log).last(6_000)}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end

  def stop_process(pid)
    return unless pid

    Process.kill("CONT", pid)
    Process.kill("TERM", pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until Process.waitpid(pid, Process::WNOHANG)
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        Process.kill("KILL", pid)
        Process.waitpid(pid)
        break
      end
      sleep 0.05
    end
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end
end

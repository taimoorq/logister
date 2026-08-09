# frozen_string_literal: true

require "aws-sdk-s3"
require "active_storage/service/disk_service"
require "base64"
require "net/http"
require "net/smtp"
require "openssl"
require "redis"
require "securerandom"
require "set"
require "stringio"
require "uri"

module InstanceConfiguration
  class Diagnostics
    Result = Struct.new(:success, :summary, :details, keyword_init: true) do
      def success?
        success == true
      end
    end

    class << self
      def call(section, values:, test_recipient: nil)
        new(section, values: values, test_recipient: test_recipient).call
      end
    end

    def initialize(section, values:, test_recipient: nil)
      @section = Registry.section!(section)
      @values = values
      @test_recipient = test_recipient.to_s.strip.presence
    end

    def call
      send("test_#{@section.key}")
    rescue StandardError => error
      Rails.logger.warn("instance configuration diagnostic failed section=#{@section.key} error=#{error.class}")
      Result.new(
        success: false,
        summary: "The #{@section.label} check failed.",
        details: { "error_class" => error.class.name }
      )
    end

    private

    def test_general
      public_uri = parse_http_uri(fetch("general.public_url"), required: true)
      docs_uri = parse_http_uri(fetch("general.docs_url"), required: true)
      raise ArgumentError, "Email sender is missing" if fetch("general.email_from").blank?

      Result.new(
        success: true,
        summary: "Canonical URLs and sender identity are valid.",
        details: { "public_host" => public_uri.host, "docs_host" => docs_uri.host }
      )
    end

    def test_background_jobs
      redis = Redis.new(
        url: background_job_redis_url,
        connect_timeout: 2,
        read_timeout: 2,
        write_timeout: 2
      )
      pong = redis.ping
      raise Redis::BaseError, "Unexpected ping response" unless pong == "PONG"

      readiness = Logister::SidekiqReadiness.new(
        redis: redis,
        concurrency: fetch("background_jobs.sidekiq_concurrency")
      ).call
      readiness["redis_roles"] = redis_role_connectivity(sidekiq_redis: redis)
      readiness["ingest_event_partitions"] = Logister::IngestEventsPartitioning.new.partition_maintenance_status(months_ahead: 3)
      worker_processes = readiness.fetch("sidekiq_processes")
      worker_pools = Array(readiness["worker_database_pools"])
      pool_valid = if worker_pools.any?
        worker_pools.all? { |pool| pool["valid"] == true }
      else
        readiness.dig("database_pool", "valid")
      end
      readiness["worker_pool_validation_source"] = worker_pools.any? ? "worker_heartbeats" : "local_process_fallback"
      success = worker_processes.positive? && pool_valid

      Result.new(
        success: success,
        summary: background_job_summary(worker_processes:, pool_valid:),
        details: readiness.merge("redis_reachable" => true)
      )
    ensure
      redis&.close
    end

    def test_email
      smtp = Net::SMTP.new(smtp_address, fetch("email.smtp_port"))
      smtp.open_timeout = fetch("email.open_timeout")
      smtp.read_timeout = fetch("email.read_timeout")
      smtp.enable_starttls_auto if fetch("email.starttls")
      smtp.start(
        fetch("email.smtp_domain"),
        fetch("email.smtp_username").presence,
        fetch("email.smtp_password").presence,
        fetch("email.smtp_username").present? ? :login : nil
      )
      smtp.finish if smtp.started?

      if @test_recipient
        InstallationMailer.configuration_test(@test_recipient, delivery: "direct").deliver_now
        InstallationMailer.configuration_test(@test_recipient, delivery: "queued").deliver_later
      end

      summary = @test_recipient ? "SMTP connected; direct and queued test messages were submitted." : "SMTP authentication and TLS negotiation succeeded."
      Result.new(success: true, summary: summary, details: { "smtp" => "reachable", "test_messages" => @test_recipient ? 2 : 0 })
    ensure
      smtp&.finish if smtp&.started?
    end

    def test_clickhouse
      mode = fetch("clickhouse.mode")
      client = Logister::ClickhouseClient.new(config: clickhouse_config)
      breaker = client.circuit_breaker_status
      if mode == "disabled"
        return Result.new(
          success: true,
          summary: "ClickHouse is disabled; PostgreSQL remains the source for reads and writes.",
          details: { "mode" => "disabled", "circuit_breaker" => breaker }
        )
      end

      schema = client.schema_status
      return Result.new(success: false, summary: "ClickHouse is reachable but its schema is not ready.", details: redacted_schema_details(schema).merge("circuit_breaker" => breaker)) unless schema[:ready]

      coverage = clickhouse_coverage(client)
      success = coverage.fetch("ready_for_reads")
      summary = if success && mode == "read_preferred"
        "ClickHouse schema and stable-window event coverage are ready; supported dashboard reads can use ClickHouse."
      elsif success
        "ClickHouse schema and stable-window event coverage are ready. Switch to read preferred to move supported dashboard reads off PostgreSQL."
      else
        "ClickHouse writes are available, but event coverage is incomplete. Keep dual write enabled and run the backfill before switching reads."
      end

      Result.new(success: success, summary: summary, details: redacted_schema_details(schema).merge(coverage).merge("circuit_breaker" => breaker))
    ensure
      client&.close
    end

    def test_archive_storage
      if fetch("archive_storage.service") == "s3"
        test_s3_archive
      else
        service = ActiveStorage::Service::DiskService.new(root: Rails.root.join("storage"))
        test_storage_service(service, service_name: "local")
      end
    end

    def test_github
      return Result.new(success: true, summary: "GitHub App integration is not configured.", details: { "configured" => false }) if fetch("github.app_id").blank? && fetch("github.private_key").blank?

      app_id = Integer(fetch("github.app_id"))
      private_key = OpenSSL::PKey::RSA.new(fetch("github.private_key").to_s.gsub("\\n", "\n"))
      uri = URI.join(fetch("github.api_url").to_s.delete_suffix("/") + "/", "app")
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["X-GitHub-Api-Version"] = fetch("github.api_version")
      request["Authorization"] = "Bearer #{github_jwt(app_id, private_key)}"
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 3
      http.read_timeout = 3
      response = http.start { |connection| connection.request(request) }
      raise IOError, "GitHub rejected the App credentials" unless response.is_a?(Net::HTTPSuccess)

      Result.new(success: true, summary: "GitHub accepted the App credentials.", details: { "configured" => true, "api_host" => uri.host })
    end

    def test_authentication
      enabled = fetch("authentication.turnstile_enabled")
      keys_valid = !enabled || (fetch("authentication.turnstile_site_key").present? && fetch("authentication.turnstile_secret_key").present?)
      limits = %w[
        authentication.public_api_rate_limit_requests
        authentication.public_api_rate_limit_period_seconds
        authentication.public_api_auth_failure_rate_limit_requests
      ].to_h { |key| [ key, fetch(key).to_i ] }
      limits_valid = limits.values.all?(&:positive?)
      valid = keys_valid && limits_valid
      summary = if !keys_valid
        "Both Turnstile keys are required when protection is enabled."
      elsif !limits_valid
        "Public API rate limits and the window must be positive integers."
      elsif enabled
        "Turnstile keys and public API limits are valid. Complete a browser challenge after activation."
      else
        "Turnstile is disabled and public API limits are valid."
      end
      Result.new(
        success: valid,
        summary: summary,
        details: { "turnstile_enabled" => enabled, "keys_present" => keys_valid, "api_limits_valid" => limits_valid }
      )
    end

    def test_public_site
      parse_http_uri(fetch("public_site.cookie_banner_base_url"), required: false)
      parse_http_uri(fetch("public_site.cookie_banner_script_url"), required: false)
      consent_ready = !fetch("public_site.cookie_consent_enabled") || fetch("public_site.cookie_banner_id").present?
      Result.new(
        success: consent_ready,
        summary: consent_ready ? "Public-site URLs and consent settings are valid." : "A Probo banner ID is required when cookie consent is enabled.",
        details: { "consent_enabled" => fetch("public_site.cookie_consent_enabled"), "analytics_configured" => analytics_configured? }
      )
    end

    def test_observability
      endpoint = parse_http_uri(fetch("observability.endpoint"), required: true)
      parse_http_uri(fetch("observability.deployment_endpoint"), required: false)
      sample_rate = Float(fetch("observability.db_metric_sample_rate"))
      raise ArgumentError, "Sample rate out of range" unless sample_rate.between?(0.0, 1.0)
      raise ArgumentError, "Web request threshold out of range" if fetch("observability.web_request_min_duration_ms").to_i.negative?
      raise ArgumentError, "Slow request threshold out of range" if fetch("observability.web_request_log_min_duration_ms").to_i.negative?

      configured = fetch("observability.api_key").present?
      Result.new(
        success: true,
        summary: configured ? "Self-monitoring configuration is valid and will apply after restart." : "Self-monitoring is not enabled; release checks can still run independently.",
        details: { "configured" => configured, "endpoint_host" => endpoint.host, "restart_required" => true }
      )
    end

    def fetch(key)
      @values.fetch(key)
    end

    def background_job_redis_url
      fetch("background_jobs.sidekiq_redis_url").presence || fetch("background_jobs.redis_url")
    end

    def redis_role_connectivity(sidekiq_redis:)
      urls = {
        "cache" => fetch("background_jobs.cache_redis_url").presence || fetch("background_jobs.redis_url"),
        "rate_limit" => fetch("background_jobs.rate_limit_redis_url").presence || fetch("background_jobs.redis_url"),
        "sidekiq" => background_job_redis_url
      }
      connections = {}

      urls.to_h do |role, url|
        connection = if url == background_job_redis_url
          sidekiq_redis
        else
          connections[url] ||= Redis.new(url: url, connect_timeout: 2, read_timeout: 2, write_timeout: 2)
        end
        raise Redis::BaseError, "Unexpected #{role} Redis ping response" unless connection.ping == "PONG"

        [ role, "reachable" ]
      end
    ensure
      connections&.each_value(&:close)
    end

    def background_job_summary(worker_processes:, pool_valid:)
      return "Redis is reachable, but no Sidekiq worker is registered. Start or restart a worker and run this check again." unless worker_processes.positive?
      return "Sidekiq is registered, but DB_POOL is smaller than worker concurrency plus operational headroom." unless pool_valid

      "Redis is reachable, Sidekiq workers are registered, and the database pool is sized for worker concurrency."
    end

    def smtp_address
      fetch("email.smtp_address").presence || "email-smtp.#{fetch('email.ses_region')}.amazonaws.com"
    end

    def parse_http_uri(value, required:)
      return if value.blank? && !required

      uri = URI.parse(value.to_s)
      raise URI::InvalidURIError, "HTTP URL required" unless uri.is_a?(URI::HTTP) && uri.host.present?

      uri
    end

    def clickhouse_config
      ActiveSupport::OrderedOptions.new.tap do |config|
        config.clickhouse_enabled = fetch("clickhouse.mode") != "disabled"
        config.clickhouse_mode = fetch("clickhouse.mode")
        config.clickhouse_url = fetch("clickhouse.url")
        config.clickhouse_database = fetch("clickhouse.database")
        config.clickhouse_events_table = fetch("clickhouse.events_table")
        config.clickhouse_spans_table = fetch("clickhouse.spans_table")
        config.clickhouse_username = fetch("clickhouse.username").presence
        config.clickhouse_password = fetch("clickhouse.password").to_s
        config.clickhouse_circuit_failure_threshold = fetch("clickhouse.circuit_failure_threshold")
        config.clickhouse_circuit_open_seconds = fetch("clickhouse.circuit_open_seconds")
      end
    end

    def clickhouse_coverage(client)
      finish = 1.hour.ago.utc.beginning_of_hour
      start = finish - 24.hours
      watermarks = TelemetryProjectionWatermark.for_clickhouse
        .where(bucket_start_at: start...finish)
        .order(:project_id, :signal, :bucket_start_at)
        .to_a
      observed = clickhouse_bucket_coverage(client, start:, finish:)
      coverage_project_ids = active_coverage_project_ids(start: start, finish: finish, watermarks: watermarks)
      capability_coverage = Logister::ClickhouseCoverage.call(
        project_ids: coverage_project_ids,
        signals: Logister::ClickhouseCoverage::EVENT_SIGNALS + [ "span" ],
        from: start,
        to: finish
      )

      gaps = watermarks.filter_map do |watermark|
        key = coverage_key(
          watermark.project_id,
          watermark.signal,
          watermark.bucket_start_at
        )
        clickhouse = observed.fetch(key, { "count" => 0, "checksum" => 0 })
        count_matches = clickhouse.fetch("count").to_i == watermark.accepted_count
        checksum_matches = clickhouse.fetch("checksum").to_i == watermark.accepted_checksum.to_i
        next if watermark.complete? && count_matches && checksum_matches

        {
          "project_id" => watermark.project_id,
          "signal" => watermark.signal,
          "bucket_start_at" => watermark.bucket_start_at.utc.iso8601,
          "accepted" => watermark.accepted_count,
          "delivered" => watermark.delivered_count,
          "clickhouse" => clickhouse.fetch("count").to_i,
          "ledger_checksum_matches" => watermark.delivered_checksum == watermark.accepted_checksum,
          "clickhouse_checksum_matches" => checksum_matches,
          "terminal_failures" => watermark.terminal_failure_count
        }
      end
      sample = clickhouse_sample_reconciliation(client, start:, finish:)
      ledger = telemetry_delivery_ledger
      postgres_count = IngestEvent.where(occurred_at: start...finish).count
      postgres_span_count = TraceSpan.where(started_at: start...finish).count
      clickhouse_count = observed.sum { |key, values| key[1] == "span" ? 0 : values.fetch("count").to_i }
      clickhouse_span_count = observed.sum { |key, values| key[1] == "span" ? values.fetch("count").to_i : 0 }
      event_coverage_present = postgres_count.zero? || watermarks.any? { |watermark| watermark.destination == "clickhouse_event" }
      span_coverage_present = postgres_span_count.zero? || watermarks.any? { |watermark| watermark.destination == "clickhouse_span" }

      {
        "coverage_window_started_at" => start.iso8601,
        "coverage_window_ended_at" => finish.iso8601,
        "postgres_events" => postgres_count,
        "clickhouse_events" => clickhouse_count,
        "postgres_spans" => postgres_span_count,
        "clickhouse_spans" => clickhouse_span_count,
        "coverage_bucket_count" => watermarks.length,
        "coverage_gap_count" => gaps.length,
        "coverage_gaps" => gaps.first(100),
        "capability_coverage" => capability_coverage.to_h,
        "sample_reconciliation" => sample,
        "delivery_ledger" => ledger,
        "ready_for_reads" => event_coverage_present && span_coverage_present && gaps.empty? && capability_coverage.complete? &&
          sample.fetch("missing_count").zero? && ledger.fetch("terminal_failures").zero?
      }
    end

    def active_coverage_project_ids(start:, finish:, watermarks:)
      project_ids = IngestEvent.where(occurred_at: start...finish).distinct.pluck(:project_id)
      project_ids.concat(TraceSpan.where(started_at: start...finish).distinct.pluck(:project_id))
      project_ids.concat(TelemetryOutboxEvent.where(recorded_at: start...finish).distinct.pluck(:project_id))
      project_ids.concat(watermarks.map(&:project_id))
      Project.where(id: project_ids.uniq, purge_requested_at: nil).pluck(:id)
    end

    def clickhouse_bucket_coverage(client, start:, finish:)
      rows = client.select_rows!(<<~SQL.squish)
        SELECT
          project_id,
          toString(event_type) AS signal,
          toStartOfHour(occurred_at) AS bucket,
          uniqExact(event_id) AS count,
          toString(sum(toUInt256(identity_checksum))) AS checksum
        FROM #{client.event_facts_table_name}
        WHERE occurred_at >= parseDateTime64BestEffort('#{start.iso8601(3)}', 3)
          AND occurred_at < parseDateTime64BestEffort('#{finish.iso8601(3)}', 3)
        GROUP BY project_id, signal, bucket
        UNION ALL
        SELECT
          project_id,
          'span' AS signal,
          toStartOfHour(started_at) AS bucket,
          uniqExact(span_id) AS count,
          toString(sum(toUInt256(identity_checksum))) AS checksum
        FROM #{client.span_facts_table_name}
        WHERE started_at >= parseDateTime64BestEffort('#{start.iso8601(3)}', 3)
          AND started_at < parseDateTime64BestEffort('#{finish.iso8601(3)}', 3)
        GROUP BY project_id, signal, bucket
      SQL

      rows.each_with_object({}) do |row, coverage|
        bucket = Time.zone.parse(row.fetch("bucket").to_s).utc.beginning_of_hour
        key = coverage_key(row.fetch("project_id"), row.fetch("signal"), bucket)
        coverage[key] = {
          "count" => row.fetch("count", 0).to_i,
          "checksum" => row.fetch("checksum", 0).to_i
        }
      end
    end

    def clickhouse_sample_reconciliation(client, start:, finish:, limit: 50)
      samples = TelemetryOutboxEvent
        .joins(:telemetry_deliveries)
        .merge(TelemetryDelivery.completed.where(destination: TelemetryDelivery::CLICKHOUSE_DESTINATIONS))
        .where(recorded_at: start...finish)
        .order(:client_identifier)
        .limit(limit)
        .map do |outbox_event|
          {
            "record_type" => outbox_event.record_type,
            "record_identifier" => outbox_event.metadata.to_h["record_identifier"].presence || outbox_event.client_identifier
          }
        end
      return { "expected_count" => 0, "present_count" => 0, "missing_count" => 0, "missing_identifiers" => [] } if samples.empty?

      event_ids = samples.filter_map { |sample| sample.fetch("record_identifier") if sample.fetch("record_type") == "IngestEvent" }
      span_ids = samples.filter_map { |sample| sample.fetch("record_identifier") if sample.fetch("record_type") == "TraceSpan" }
      branches = []
      if event_ids.any?
        branches << <<~SQL.squish
          SELECT toString(event_id) AS record_identifier
          FROM #{client.event_facts_table_name}
          WHERE event_id IN (#{clickhouse_uuid_list(event_ids)})
          GROUP BY event_id
        SQL
      end
      if span_ids.any?
        branches << <<~SQL.squish
          SELECT toString(span_id) AS record_identifier
          FROM #{client.span_facts_table_name}
          WHERE span_id IN (#{clickhouse_uuid_list(span_ids)})
          GROUP BY span_id
        SQL
      end
      present = client.select_rows!(branches.join(" UNION ALL ")).map { |row| row.fetch("record_identifier").downcase }.to_set
      expected = samples.map { |sample| sample.fetch("record_identifier").downcase }.to_set
      missing = expected - present

      {
        "expected_count" => expected.length,
        "present_count" => (expected & present).length,
        "missing_count" => missing.length,
        "missing_identifiers" => missing.first(20)
      }
    end

    def telemetry_delivery_ledger
      now = Time.current
      oldest = TelemetryDelivery.incomplete.minimum(:created_at)
      {
        "pending" => TelemetryDelivery.pending.count,
        "retrying" => TelemetryDelivery.retrying.count,
        "processing" => TelemetryDelivery.processing.count,
        "terminal_failures" => TelemetryDelivery.terminal_failed.count,
        "oldest_incomplete_at" => oldest&.utc&.iso8601,
        "oldest_incomplete_age_seconds" => oldest ? (now - oldest).to_i : 0,
        "max_attempts" => TelemetryDelivery.incomplete.maximum(:attempts).to_i
      }
    end

    def clickhouse_uuid_list(values)
      Array(values).map do |value|
        uuid = Logister::TelemetryIdentity.normalize_uuid(value)
        raise ArgumentError, "Invalid telemetry UUID in coverage sample" unless uuid

        "toUUID('#{uuid}')"
      end.join(", ")
    end

    def coverage_key(project_id, signal, bucket)
      [ project_id.to_i, signal.to_s, bucket.utc.beginning_of_hour ]
    end

    def redacted_schema_details(schema)
      {
        "healthy" => schema[:healthy] == true,
        "ready" => schema[:ready] == true,
        "database" => schema[:database].to_s,
        "missing_tables" => Array(schema[:missing_tables]),
        "schema_issues" => Array(schema[:schema_issues])
      }
    end

    def test_s3_archive
      credentials = Aws::Credentials.new(fetch("archive_storage.access_key_id"), fetch("archive_storage.secret_access_key"))
      options = {
        region: fetch("archive_storage.region"),
        credentials: credentials,
        force_path_style: fetch("archive_storage.force_path_style")
      }
      options[:endpoint] = fetch("archive_storage.endpoint") if fetch("archive_storage.endpoint").present?
      client = Aws::S3::Client.new(**options)
      bucket = fetch("archive_storage.bucket")
      raise ArgumentError, "Archive bucket is required" if bucket.blank?

      key = [ fetch("archive_storage.prefix").presence, ".logister-configuration-test-#{SecureRandom.uuid}" ].compact.join("/")
      body = SecureRandom.hex(24)
      client.put_object(bucket: bucket, key: key, body: body)
      downloaded = client.get_object(bucket: bucket, key: key).body.read
      raise IOError, "Archive read-back did not match" unless ActiveSupport::SecurityUtils.secure_compare(body, downloaded)

      Result.new(success: true, summary: "S3 write, read, and delete checks succeeded.", details: { "service" => "s3", "bucket" => bucket })
    ensure
      client&.delete_object(bucket: bucket, key: key) if bucket.present? && key.present?
    end

    def test_storage_service(service, service_name:)
      key = ".logister-configuration-test-#{SecureRandom.uuid}"
      body = SecureRandom.hex(24)
      service.upload(key, StringIO.new(body))
      downloaded = service.download(key)
      raise IOError, "Archive read-back did not match" unless ActiveSupport::SecurityUtils.secure_compare(body, downloaded)

      Result.new(success: true, summary: "Local archive write, read, and delete checks succeeded.", details: { "service" => service_name })
    ensure
      service&.delete(key) if key.present?
    end

    def github_jwt(app_id, private_key)
      now = Time.current.to_i
      header = { alg: "RS256", typ: "JWT" }
      payload = { iat: now - 30, exp: now + 8.minutes.to_i, iss: app_id }
      encoded = [ header, payload ].map { |part| Base64.urlsafe_encode64(part.to_json, padding: false) }.join(".")
      signature = private_key.sign(OpenSSL::Digest::SHA256.new, encoded)
      "#{encoded}.#{Base64.urlsafe_encode64(signature, padding: false)}"
    end

    def analytics_configured?
      fetch("public_site.google_tag_id").present? || fetch("public_site.cloudflare_analytics_token").present?
    end
  end
end

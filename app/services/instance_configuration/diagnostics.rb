# frozen_string_literal: true

require "aws-sdk-s3"
require "active_storage/service/disk_service"
require "base64"
require "net/http"
require "net/smtp"
require "openssl"
require "redis"
require "securerandom"
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
        url: fetch("background_jobs.redis_url"),
        connect_timeout: 2,
        read_timeout: 2,
        write_timeout: 2
      )
      pong = redis.ping
      worker_processes = redis.scard("processes")
      raise Redis::BaseError, "Unexpected ping response" unless pong == "PONG"

      Result.new(
        success: worker_processes.positive?,
        summary: worker_processes.positive? ? "Redis is reachable and Sidekiq workers are registered." : "Redis is reachable, but no Sidekiq worker is registered. Start or restart a worker and run this check again.",
        details: { "redis" => "reachable", "sidekiq_processes" => worker_processes }
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
      return Result.new(success: true, summary: "ClickHouse is disabled; PostgreSQL remains the source for reads and writes.", details: { "mode" => "disabled" }) if mode == "disabled"

      client = Logister::ClickhouseClient.new(config: clickhouse_config)
      schema = client.schema_status
      return Result.new(success: false, summary: "ClickHouse is reachable but its schema is not ready.", details: redacted_schema_details(schema)) unless schema[:ready]

      coverage = clickhouse_coverage(client)
      success = coverage.fetch("ready_for_reads")
      summary = if success && mode == "read_preferred"
        "ClickHouse schema and stable-window event coverage are ready; supported dashboard reads can use ClickHouse."
      elsif success
        "ClickHouse schema and stable-window event coverage are ready. Switch to read preferred to move supported dashboard reads off PostgreSQL."
      else
        "ClickHouse writes are available, but event coverage is incomplete. Keep dual write enabled and run the backfill before switching reads."
      end

      Result.new(success: success, summary: summary, details: redacted_schema_details(schema).merge(coverage))
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
      end
    end

    def clickhouse_coverage(client)
      finish = 5.minutes.ago.utc
      start = finish - 24.hours
      postgres_count = IngestEvent.where(occurred_at: start...finish).count
      rows = client.select_rows!(<<~SQL.squish)
        SELECT uniqExact(event_id) AS count
        FROM #{client.events_table_name}
        WHERE occurred_at >= parseDateTime64BestEffort('#{start.iso8601(3)}', 3)
          AND occurred_at < parseDateTime64BestEffort('#{finish.iso8601(3)}', 3)
      SQL
      clickhouse_count = rows.first&.fetch("count", 0).to_i

      {
        "coverage_window_started_at" => start.iso8601,
        "coverage_window_ended_at" => finish.iso8601,
        "postgres_events" => postgres_count,
        "clickhouse_events" => clickhouse_count,
        "ready_for_reads" => clickhouse_count >= postgres_count
      }
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

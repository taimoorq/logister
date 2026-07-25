# frozen_string_literal: true

require "uri"

module InstanceConfiguration
  module Runtime
    module_function

    def apply!
      apply_clickhouse!
      apply_url_options!
      apply_mailer!
      apply_turnstile!
      apply_cache!
      apply_operational_limits!
      apply_observability!
    rescue ActiveRecord::StatementInvalid => error
      Rails.logger.info("instance configuration database is not ready: #{error.class}")
    end

    def apply_clickhouse!
      config = Rails.application.config.x.logister
      mode = InstanceConfiguration.value("clickhouse.mode")
      config.clickhouse_mode = mode
      config.clickhouse_enabled = mode != "disabled"
      config.clickhouse_url = InstanceConfiguration.value("clickhouse.url")
      config.clickhouse_database = InstanceConfiguration.value("clickhouse.database")
      config.clickhouse_events_table = InstanceConfiguration.value("clickhouse.events_table")
      config.clickhouse_spans_table = InstanceConfiguration.value("clickhouse.spans_table")
      config.clickhouse_username = InstanceConfiguration.value("clickhouse.username").presence
      config.clickhouse_password = InstanceConfiguration.value("clickhouse.password").to_s
    end

    def apply_url_options!
      uri = URI.parse(InstanceConfiguration.value("general.public_url"))
      return unless uri.host

      options = { host: uri.host, protocol: uri.scheme }
      options[:port] = uri.port unless [ 80, 443 ].include?(uri.port)
      Rails.application.routes.default_url_options = options
      ActionMailer::Base.default_url_options = options
    rescue URI::InvalidURIError
      nil
    end

    def apply_mailer!
      ActionMailer::Base.smtp_settings = {
        address: InstanceConfiguration.value("email.smtp_address").presence || "email-smtp.#{InstanceConfiguration.value('email.ses_region')}.amazonaws.com",
        port: InstanceConfiguration.value("email.smtp_port"),
        domain: InstanceConfiguration.value("email.smtp_domain"),
        user_name: InstanceConfiguration.value("email.smtp_username").presence,
        password: InstanceConfiguration.value("email.smtp_password").presence,
        authentication: :login,
        enable_starttls_auto: InstanceConfiguration.value("email.starttls"),
        open_timeout: InstanceConfiguration.value("email.open_timeout"),
        read_timeout: InstanceConfiguration.value("email.read_timeout")
      }
      ActionMailer::Base.default from: InstanceConfiguration.value("general.email_from")
      Devise.mailer_sender = InstanceConfiguration.value("general.email_from")
    end

    def apply_turnstile!
      site_key = InstanceConfiguration.value("authentication.turnstile_site_key")
      secret_key = InstanceConfiguration.value("authentication.turnstile_secret_key")
      enabled = InstanceConfiguration.value("authentication.turnstile_enabled")
      RailsCloudflareTurnstile.configuration.site_key = site_key
      RailsCloudflareTurnstile.configuration.secret_key = secret_key
      RailsCloudflareTurnstile.configuration.enabled = enabled && site_key.present? && secret_key.present?
    end

    def apply_cache!
      return unless Rails.env.production?

      Rails.cache = ActiveSupport::Cache.lookup_store(
        :redis_cache_store,
        url: InstanceConfiguration.value("background_jobs.redis_url"),
        namespace: "logister:cache:production",
        connect_timeout: 2,
        read_timeout: 2,
        write_timeout: 2,
        reconnect_attempts: 2,
        error_handler: lambda do |method:, returning:, exception:|
          Rails.logger.warn("Redis cache error in production: #{method} => #{returning.inspect} (#{exception.class})")
        end
      )
    end

    def apply_operational_limits!
      config = Rails.application.config.x.logister
      config.public_api_rate_limit_requests = InstanceConfiguration.value("authentication.public_api_rate_limit_requests")
      config.public_api_rate_limit_period_seconds = InstanceConfiguration.value("authentication.public_api_rate_limit_period_seconds")
      config.public_api_auth_failure_rate_limit_requests = InstanceConfiguration.value("authentication.public_api_auth_failure_rate_limit_requests")
      config.web_request_transactions_enabled = InstanceConfiguration.value("observability.capture_web_transactions")
      config.web_request_min_duration_ms = InstanceConfiguration.value("observability.web_request_min_duration_ms").to_f
      config.web_request_log_min_duration_ms = InstanceConfiguration.value("observability.web_request_log_min_duration_ms").to_f
    end

    def apply_observability!
      return unless Logister.respond_to?(:configure)

      Logister.configure do |config|
        config.api_key = InstanceConfiguration.value("observability.api_key")
        config.endpoint = InstanceConfiguration.value("observability.endpoint")
        if config.respond_to?(:deployment_endpoint=)
          config.deployment_endpoint = InstanceConfiguration.value("observability.deployment_endpoint").presence
        end
        config.capture_request_spans = InstanceConfiguration.value("observability.capture_request_spans")
        config.capture_db_metrics = InstanceConfiguration.value("observability.capture_db_metrics")
        config.db_metric_min_duration_ms = InstanceConfiguration.value("observability.db_metric_min_duration_ms").to_f
        config.db_metric_sample_rate = InstanceConfiguration.value("observability.db_metric_sample_rate").to_f
        config.capture_sql_breadcrumbs = InstanceConfiguration.value("observability.capture_sql_breadcrumbs")
        config.sql_breadcrumb_min_duration_ms = InstanceConfiguration.value("observability.sql_breadcrumb_min_duration_ms").to_f
      end
    end
  end
end

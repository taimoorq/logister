# frozen_string_literal: true

module InstanceConfiguration
  class Registry
    Definition = Struct.new(
      :key, :section, :label, :env_key, :type, :default, :secret, :restart_required,
      :help, :placeholder, :options, keyword_init: true
    ) do
      def secret?
        secret == true
      end

      def restart_required?
        restart_required == true
      end
    end

    Section = Struct.new(:key, :label, :description, :required, keyword_init: true) do
      def required?
        required == true
      end

      def slug
        key.tr("_", "-")
      end
    end

    SECTIONS = [
      Section.new(key: "general", label: "General", description: "Canonical URLs and instance identity.", required: true),
      Section.new(key: "background_jobs", label: "Redis & jobs", description: "Redis cache, Sidekiq queues, and worker readiness.", required: true),
      Section.new(key: "email", label: "Email", description: "SMTP for confirmations, password resets, invitations, and alerts; optional for a single-operator install.", required: false),
      Section.new(key: "clickhouse", label: "ClickHouse", description: "Optional analytics writes, schema, backfill, and read cutover.", required: false),
      Section.new(key: "archive_storage", label: "Archive storage", description: "Local or S3-compatible telemetry archives.", required: false),
      Section.new(key: "github", label: "GitHub App", description: "Private source lookup, repository sync, and issue creation.", required: false),
      Section.new(key: "authentication", label: "Authentication", description: "Bot protection and global public API rate limits.", required: false),
      Section.new(key: "public_site", label: "Public site", description: "Documentation, consent banner, and analytics settings.", required: false),
      Section.new(key: "observability", label: "Observability", description: "Self-monitoring and release update checks.", required: false)
    ].freeze

    DEFINITIONS = [
      Definition.new(key: "general.public_url", section: "general", label: "Public URL", env_key: "LOGISTER_PUBLIC_URL", type: :url, default: "https://logister.org", help: "Canonical HTTPS origin used in mail, metadata, and generated links.", placeholder: "https://errors.example.com"),
      Definition.new(key: "general.docs_url", section: "general", label: "Documentation URL", env_key: "LOGISTER_DOCS_URL", type: :url, default: "https://logister.org/docs", help: "Base URL for documentation links shown inside Logister.", placeholder: "https://errors.example.com/docs"),
      Definition.new(key: "general.email_from", section: "general", label: "Default email sender", env_key: "LOGISTER_EMAIL_FROM", type: :string, default: "support@logister.org", help: "From address for confirmations, invitations, and project notices.", placeholder: "logister@example.com"),
      Definition.new(key: "general.api_key_prefix", section: "general", label: "Project API key prefix", env_key: "LOGISTER_API_KEY_PREFIX", type: :string, default: "logister", restart_required: true, help: "Prefix applied to newly generated project tokens.", placeholder: "logister"),

      Definition.new(key: "background_jobs.redis_url", section: "background_jobs", label: "Redis URL", env_key: "REDIS_URL", type: :secret, default: "redis://127.0.0.1:6379/0", secret: true, restart_required: true, help: "Used by the production cache and every Sidekiq web or worker process.", placeholder: "rediss://user:password@host:6379/0"),
      Definition.new(key: "background_jobs.sidekiq_concurrency", section: "background_jobs", label: "Worker concurrency", env_key: "SIDEKIQ_CONCURRENCY", type: :integer, default: 5, restart_required: true, help: "Number of jobs one Sidekiq process may execute concurrently.", placeholder: "5"),

      Definition.new(key: "email.smtp_address", section: "email", label: "SMTP server", env_key: "SES_SMTP_ADDRESS", type: :string, default: nil, help: "SMTP hostname. When blank, Logister derives the Amazon SES hostname from the region.", placeholder: "email-smtp.us-east-1.amazonaws.com"),
      Definition.new(key: "email.smtp_port", section: "email", label: "SMTP port", env_key: "SES_SMTP_PORT", type: :integer, default: 587, help: "Usually 587 with STARTTLS.", placeholder: "587"),
      Definition.new(key: "email.smtp_domain", section: "email", label: "SMTP domain", env_key: "SES_SMTP_DOMAIN", type: :string, default: "logister.org", help: "HELO domain sent to the SMTP server.", placeholder: "example.com"),
      Definition.new(key: "email.smtp_username", section: "email", label: "SMTP username", env_key: "SES_SMTP_USERNAME", type: :string, default: nil, help: "SMTP credential username.", placeholder: "SMTP username"),
      Definition.new(key: "email.smtp_password", section: "email", label: "SMTP password", env_key: "SES_SMTP_PASSWORD", type: :secret, default: nil, secret: true, help: "Stored encrypted and never displayed after saving.", placeholder: "SMTP password"),
      Definition.new(key: "email.ses_region", section: "email", label: "SES region", env_key: "SES_REGION", type: :string, default: "us-east-1", help: "Used to derive the SES SMTP hostname when no server is supplied.", placeholder: "us-east-1"),
      Definition.new(key: "email.starttls", section: "email", label: "Enable STARTTLS", env_key: "SES_SMTP_ENABLE_STARTTLS_AUTO", type: :boolean, default: true, help: "Upgrade the SMTP connection with TLS when the server supports it."),
      Definition.new(key: "email.open_timeout", section: "email", label: "Open timeout (seconds)", env_key: "SES_SMTP_OPEN_TIMEOUT", type: :integer, default: 5, help: "Maximum time allowed to open the SMTP connection.", placeholder: "5"),
      Definition.new(key: "email.read_timeout", section: "email", label: "Read timeout (seconds)", env_key: "SES_SMTP_READ_TIMEOUT", type: :integer, default: 5, help: "Maximum time allowed for an SMTP response.", placeholder: "5"),
      Definition.new(key: "email.configuration_set", section: "email", label: "SES configuration set", env_key: "SES_CONFIGURATION_SET", type: :string, default: nil, help: "Optional Amazon SES delivery metrics configuration set.", placeholder: "logister-production"),

      Definition.new(key: "clickhouse.mode", section: "clickhouse", label: "Activation mode", env_key: "LOGISTER_CLICKHOUSE_MODE", type: :select, default: "disabled", restart_required: true, help: "Use dual write first. Read preferred is allowed only after schema and coverage verification.", options: [ [ "Disabled", "disabled" ], [ "Dual write", "dual_write" ], [ "Read preferred", "read_preferred" ] ]),
      Definition.new(key: "clickhouse.url", section: "clickhouse", label: "HTTP endpoint", env_key: "LOGISTER_CLICKHOUSE_URL", type: :url, default: "http://127.0.0.1:8123", help: "ClickHouse HTTP or ClickHouse Cloud query endpoint.", placeholder: "https://cluster.example:8443"),
      Definition.new(key: "clickhouse.database", section: "clickhouse", label: "Database", env_key: "LOGISTER_CLICKHOUSE_DATABASE", type: :string, default: "logister", help: "Database containing Logister analytics tables.", placeholder: "logister"),
      Definition.new(key: "clickhouse.events_table", section: "clickhouse", label: "Events table", env_key: "LOGISTER_CLICKHOUSE_EVENTS_TABLE", type: :string, default: "events_raw", help: "Raw event table name.", placeholder: "events_raw"),
      Definition.new(key: "clickhouse.spans_table", section: "clickhouse", label: "Spans table", env_key: "LOGISTER_CLICKHOUSE_SPANS_TABLE", type: :string, default: "spans_raw", help: "Raw span table name.", placeholder: "spans_raw"),
      Definition.new(key: "clickhouse.username", section: "clickhouse", label: "Runtime username", env_key: "LOGISTER_CLICKHOUSE_USERNAME", type: :string, default: "default", help: "Least-privilege account for inserts and analytics queries.", placeholder: "default"),
      Definition.new(key: "clickhouse.password", section: "clickhouse", label: "Runtime password", env_key: "LOGISTER_CLICKHOUSE_PASSWORD", type: :secret, default: nil, secret: true, help: "Stored encrypted and never displayed after saving.", placeholder: "ClickHouse password"),
      Definition.new(key: "clickhouse.migration_username", section: "clickhouse", label: "Schema username", env_key: "LOGISTER_CLICKHOUSE_MIGRATION_USERNAME", type: :string, default: nil, help: "Optional DDL account used for schema repair.", placeholder: "logister_schema"),
      Definition.new(key: "clickhouse.migration_password", section: "clickhouse", label: "Schema password", env_key: "LOGISTER_CLICKHOUSE_MIGRATION_PASSWORD", type: :secret, default: nil, secret: true, help: "Optional DDL credential, stored encrypted.", placeholder: "Schema password"),
      Definition.new(key: "clickhouse.failure_throttle_seconds", section: "clickhouse", label: "Failure report throttle", env_key: "LOGISTER_CLICKHOUSE_FAILURE_THROTTLE_SECONDS", type: :integer, default: 60, help: "Minimum seconds between self-monitoring reports for a ClickHouse outage.", placeholder: "60"),

      Definition.new(key: "archive_storage.service", section: "archive_storage", label: "Archive service", env_key: "LOGISTER_ARCHIVE_STORAGE_SERVICE", type: :select, default: "local", restart_required: true, help: "Keep archives on local storage or write them to S3-compatible object storage.", options: [ [ "Local disk", "local" ], [ "S3 compatible", "s3" ] ]),
      Definition.new(key: "archive_storage.access_key_id", section: "archive_storage", label: "Access key ID", env_key: "AWS_ACCESS_KEY_ID", type: :string, default: nil, help: "Least-privilege access key for the archive bucket.", placeholder: "Access key ID"),
      Definition.new(key: "archive_storage.secret_access_key", section: "archive_storage", label: "Secret access key", env_key: "AWS_SECRET_ACCESS_KEY", type: :secret, default: nil, secret: true, help: "Stored encrypted and never displayed after saving.", placeholder: "Secret access key"),
      Definition.new(key: "archive_storage.region", section: "archive_storage", label: "Region", env_key: "AWS_REGION", type: :string, default: "us-east-1", help: "S3 region.", placeholder: "us-east-1"),
      Definition.new(key: "archive_storage.bucket", section: "archive_storage", label: "Bucket", env_key: "AWS_S3_BUCKET", type: :string, default: nil, help: "Private bucket used for telemetry archives.", placeholder: "logister-archives"),
      Definition.new(key: "archive_storage.endpoint", section: "archive_storage", label: "Custom endpoint", env_key: "AWS_S3_ENDPOINT", type: :url, default: nil, help: "Optional endpoint for an S3-compatible provider.", placeholder: "https://s3.example.com"),
      Definition.new(key: "archive_storage.force_path_style", section: "archive_storage", label: "Force path-style URLs", env_key: "AWS_S3_FORCE_PATH_STYLE", type: :boolean, default: false, help: "Required by some S3-compatible providers."),
      Definition.new(key: "archive_storage.prefix", section: "archive_storage", label: "Archive prefix", env_key: "LOGISTER_ARCHIVE_PREFIX", type: :string, default: "telemetry", help: "Object key prefix for exported telemetry.", placeholder: "telemetry"),

      Definition.new(key: "github.app_id", section: "github", label: "App ID", env_key: "LOGISTER_GITHUB_APP_ID", type: :string, default: nil, help: "Numeric GitHub App identifier.", placeholder: "123456"),
      Definition.new(key: "github.private_key", section: "github", label: "Private key", env_key: "LOGISTER_GITHUB_APP_PRIVATE_KEY", type: :textarea_secret, default: nil, secret: true, help: "PEM private key for App authentication.", placeholder: "-----BEGIN RSA PRIVATE KEY-----"),
      Definition.new(key: "github.webhook_secret", section: "github", label: "Webhook secret", env_key: "LOGISTER_GITHUB_WEBHOOK_SECRET", type: :secret, default: nil, secret: true, help: "Secret used to verify GitHub webhook signatures.", placeholder: "Webhook secret"),
      Definition.new(key: "github.app_slug", section: "github", label: "App slug", env_key: "LOGISTER_GITHUB_APP_SLUG", type: :string, default: nil, help: "GitHub App slug used to build the installation URL.", placeholder: "your-logister-app"),
      Definition.new(key: "github.install_url", section: "github", label: "Install URL", env_key: "LOGISTER_GITHUB_APP_INSTALL_URL", type: :url, default: nil, help: "Optional explicit GitHub App installation URL.", placeholder: "https://github.com/apps/your-app/installations/new"),
      Definition.new(key: "github.api_url", section: "github", label: "API URL", env_key: "LOGISTER_GITHUB_API_URL", type: :url, default: "https://api.github.com", help: "GitHub API or GitHub Enterprise API base URL.", placeholder: "https://api.github.com"),
      Definition.new(key: "github.web_url", section: "github", label: "Web URL", env_key: "LOGISTER_GITHUB_WEB_URL", type: :url, default: "https://github.com", help: "GitHub or GitHub Enterprise web origin.", placeholder: "https://github.com"),
      Definition.new(key: "github.api_version", section: "github", label: "API version", env_key: "LOGISTER_GITHUB_API_VERSION", type: :string, default: "2026-03-10", help: "Version sent in GitHub API requests.", placeholder: "2026-03-10"),
      Definition.new(key: "github.stateless_s2s_token", section: "github", label: "Stateless S2S token override", env_key: "LOGISTER_GITHUB_STATELESS_S2S_TOKEN", type: :select, default: "", help: "Optional GitHub rollout override. Leave automatic unless diagnosing a token issue.", options: [ [ "Automatic", "" ], [ "Enabled", "enabled" ], [ "Disabled", "disabled" ] ]),

      Definition.new(key: "authentication.turnstile_enabled", section: "authentication", label: "Enable Turnstile", env_key: "LOGISTER_TURNSTILE_ENABLED", type: :boolean, default: false, restart_required: true, help: "Require Cloudflare Turnstile on public Devise forms."),
      Definition.new(key: "authentication.turnstile_site_key", section: "authentication", label: "Turnstile site key", env_key: "LOGISTER_TURNSTILE_SITE_KEY", type: :string, default: nil, restart_required: true, help: "Public site key rendered on account forms.", placeholder: "Site key"),
      Definition.new(key: "authentication.turnstile_secret_key", section: "authentication", label: "Turnstile secret key", env_key: "LOGISTER_TURNSTILE_SECRET_KEY", type: :secret, default: nil, secret: true, restart_required: true, help: "Secret used for server-side verification.", placeholder: "Secret key"),
      Definition.new(key: "authentication.public_api_rate_limit_requests", section: "authentication", label: "Accepted API requests", env_key: "LOGISTER_PUBLIC_API_RATE_LIMIT_REQUESTS", type: :integer, default: 1200, help: "Global accepted-request limit per project API token and endpoint during each window.", placeholder: "1200"),
      Definition.new(key: "authentication.public_api_rate_limit_period_seconds", section: "authentication", label: "API rate-limit window (seconds)", env_key: "LOGISTER_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS", type: :integer, default: 60, help: "Window used by the global public ingestion API limit.", placeholder: "60"),
      Definition.new(key: "authentication.public_api_auth_failure_rate_limit_requests", section: "authentication", label: "Authentication failure limit", env_key: "LOGISTER_PUBLIC_API_AUTH_FAILURE_RATE_LIMIT_REQUESTS", type: :integer, default: 120, help: "Failed public API authentication attempts allowed per source IP during each window.", placeholder: "120"),

      Definition.new(key: "public_site.analytics_enabled", section: "public_site", label: "Enable analytics outside production", env_key: "LOGISTER_ANALYTICS_ENABLED", type: :boolean, default: false, help: "Production analytics are enabled when an analytics token is configured."),
      Definition.new(key: "public_site.google_tag_id", section: "public_site", label: "Google tag ID", env_key: "GOOGLE_TAG_ID", type: :string, default: nil, help: "Optional consent-gated Google Analytics measurement ID.", placeholder: "G-XXXXXXXXXX"),
      Definition.new(key: "public_site.cloudflare_analytics_token", section: "public_site", label: "Cloudflare analytics token", env_key: "CLOUDFLARE_WEB_ANALYTICS_TOKEN", type: :secret, default: nil, secret: true, help: "Optional consent-gated Cloudflare Web Analytics token.", placeholder: "Analytics token"),
      Definition.new(key: "public_site.cookie_consent_enabled", section: "public_site", label: "Enable cookie consent", env_key: "LOGISTER_COOKIE_CONSENT_ENABLED", type: :boolean, default: true, help: "Render the Probo consent banner when its ID and API are configured."),
      Definition.new(key: "public_site.cookie_banner_id", section: "public_site", label: "Probo banner ID", env_key: "PROBO_COOKIE_BANNER_ID", type: :string, default: nil, help: "Banner identifier from Probo.", placeholder: "Banner ID"),
      Definition.new(key: "public_site.cookie_banner_base_url", section: "public_site", label: "Probo API base URL", env_key: "PROBO_COOKIE_BANNER_BASE_URL", type: :url, default: nil, help: "Upstream Probo API base URL.", placeholder: "https://probo.example.com"),
      Definition.new(key: "public_site.cookie_banner_script_url", section: "public_site", label: "Banner script URL", env_key: "PROBO_COOKIE_BANNER_SCRIPT_URL", type: :url, default: "https://cdn.jsdelivr.net/npm/@probo/cookie-banner/dist/cookie-banner.iife.js", help: "Browser script used to render the banner."),
      Definition.new(key: "public_site.cookie_banner_proxy_enabled", section: "public_site", label: "Proxy banner API", env_key: "PROBO_COOKIE_BANNER_PROXY_ENABLED", type: :boolean, default: true, help: "Proxy the Probo API through Logister so browser requests remain same-origin."),
      Definition.new(key: "public_site.cookie_banner_position", section: "public_site", label: "Banner position", env_key: "PROBO_COOKIE_BANNER_POSITION", type: :select, default: "bottom-left", help: "Location of the consent control.", options: [ [ "Bottom left", "bottom-left" ], [ "Bottom right", "bottom-right" ] ]),
      Definition.new(key: "public_site.analytics_cookie_category", section: "public_site", label: "Analytics consent category", env_key: "LOGISTER_ANALYTICS_COOKIE_CATEGORY", type: :string, default: "analytics", help: "Probo category slug that permits analytics scripts.", placeholder: "analytics"),

      Definition.new(key: "observability.api_key", section: "observability", label: "Self-monitoring API key", env_key: "LOGISTER_API_KEY", type: :secret, default: nil, secret: true, restart_required: true, help: "Project API key used by this Logister instance to report its own telemetry.", placeholder: "Project API key"),
      Definition.new(key: "observability.endpoint", section: "observability", label: "Event endpoint", env_key: "LOGISTER_ENDPOINT", type: :url, default: "https://logister.org/api/v1/ingest_events", restart_required: true, help: "Ingestion endpoint for this instance's own telemetry.", placeholder: "https://errors.example.com/api/v1/ingest_events"),
      Definition.new(key: "observability.deployment_endpoint", section: "observability", label: "Deployment endpoint", env_key: "LOGISTER_DEPLOYMENT_ENDPOINT", type: :url, default: nil, restart_required: true, help: "Optional deployment reporting endpoint.", placeholder: "https://errors.example.com/api/v1/deployments"),
      Definition.new(key: "observability.capture_request_spans", section: "observability", label: "Capture request spans", env_key: "LOGISTER_CAPTURE_REQUEST_SPANS", type: :boolean, default: true, restart_required: true, help: "Record top-level Rails request spans."),
      Definition.new(key: "observability.capture_db_metrics", section: "observability", label: "Capture database metrics", env_key: "LOGISTER_CAPTURE_DB_METRICS", type: :boolean, default: true, restart_required: true, help: "Report slow Active Record queries as metrics."),
      Definition.new(key: "observability.db_metric_min_duration_ms", section: "observability", label: "Database metric threshold (ms)", env_key: "LOGISTER_DB_METRIC_MIN_DURATION_MS", type: :integer, default: 250, restart_required: true, help: "Ignore faster database queries.", placeholder: "250"),
      Definition.new(key: "observability.db_metric_sample_rate", section: "observability", label: "Database metric sample rate", env_key: "LOGISTER_DB_METRIC_SAMPLE_RATE", type: :string, default: "1.0", restart_required: true, help: "Decimal sampling rate from 0.0 to 1.0.", placeholder: "1.0"),
      Definition.new(key: "observability.capture_sql_breadcrumbs", section: "observability", label: "Capture SQL breadcrumbs", env_key: "LOGISTER_CAPTURE_SQL_BREADCRUMBS", type: :boolean, default: true, restart_required: true, help: "Attach slow query breadcrumbs to self-reported events."),
      Definition.new(key: "observability.sql_breadcrumb_min_duration_ms", section: "observability", label: "SQL breadcrumb threshold (ms)", env_key: "LOGISTER_SQL_BREADCRUMB_MIN_DURATION_MS", type: :integer, default: 25, restart_required: true, help: "Ignore faster SQL breadcrumbs.", placeholder: "25"),
      Definition.new(key: "observability.capture_web_transactions", section: "observability", label: "Capture web transactions", env_key: "LOGISTER_CAPTURE_WEB_REQUEST_TRANSACTIONS", type: :boolean, default: true, restart_required: true, help: "Report request transactions through the Ruby integration."),
      Definition.new(key: "observability.web_request_min_duration_ms", section: "observability", label: "Web request threshold (ms)", env_key: "LOGISTER_WEB_REQUEST_MIN_DURATION_MS", type: :integer, default: 250, help: "Ignore faster Rails requests in self-observability performance reporting.", placeholder: "250"),
      Definition.new(key: "observability.web_request_log_min_duration_ms", section: "observability", label: "Slow request log threshold (ms)", env_key: "LOGISTER_WEB_REQUEST_LOG_MIN_DURATION_MS", type: :integer, default: 1000, help: "Report request log events at warning level at or above this duration.", placeholder: "1000"),
      Definition.new(key: "observability.update_checks_enabled", section: "observability", label: "Check for releases", env_key: "LOGISTER_UPDATE_CHECKS_ENABLED", type: :boolean, default: true, help: "Check GitHub daily for a newer Logister release."),
      Definition.new(key: "observability.release_repository", section: "observability", label: "Release repository", env_key: "LOGISTER_RELEASE_REPOSITORY", type: :string, default: "taimoorq/logister", help: "GitHub repository used for update checks.", placeholder: "owner/repository"),
      Definition.new(key: "observability.github_token", section: "observability", label: "GitHub API token", env_key: "LOGISTER_GITHUB_TOKEN", type: :secret, default: nil, secret: true, help: "Optional token for private forks or higher release-check rate limits.", placeholder: "GitHub token")
    ].freeze

    class << self
      def sections
        SECTIONS
      end

      def section(key)
        normalized_key = key.to_s.tr("-", "_")
        sections.find { |section| section.key == normalized_key }
      end

      def section!(key)
        section(key) || raise(KeyError, "Unknown installation section: #{key.inspect}")
      end

      def definitions
        DEFINITIONS
      end

      def definition(key)
        definitions.find { |definition| definition.key == key.to_s }
      end

      def definition!(key)
        definition(key) || raise(KeyError, "Unknown instance setting: #{key.inspect}")
      end

      def definitions_for(section_key)
        section!(section_key)
        definitions.select { |definition| definition.section == section_key.to_s }
      end

      def required_section_keys
        sections.select(&:required?).map(&:key)
      end
    end
  end
end

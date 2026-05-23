require "digest"

module Seeds
  module_function

  def run!
    unless Rails.env.development?
      puts "[seeds] Skipping sample data for #{Rails.env} environment."
      return
    end

    users = seed_users
    projects = seed_projects(users)
    seed_memberships(users, projects)
    keys = seed_api_keys(projects)
    seed_events(projects, keys)
    cleanup_non_check_in_monitors(projects)
    seed_trace_spans(projects, keys)
    seed_group_states(projects.fetch(:storefront))
    seed_retention_policies(projects)
    seed_notification_preferences(users, projects)
    seed_notification_deliveries(users, projects)
    seed_telemetry_archives(projects)

    puts "[seeds] Development sample data created/updated."
    puts "[seeds] Sign in with:"
    puts "  - alice@example.com / password123"
    puts "  - bob@example.com / password123"
    puts "  - carol@example.com / password123"
  end

  def seed_users
    {
      alice: upsert_user!("alice@example.com", "Alice Operator"),
      bob: upsert_user!("bob@example.com", "Bob Builder"),
      carol: upsert_user!("carol@example.com", "Carol Collaborator")
    }
  end

  def seed_projects(users)
    {
      storefront: upsert_project!(
        owner: users.fetch(:alice),
        slug: "storefront",
        name: "Storefront",
        description: "Rails storefront app with checkout, search, and background jobs.",
        integration_kind: "ruby"
      ),
      billing_worker: upsert_project!(
        owner: users.fetch(:alice),
        slug: "billing-worker",
        name: "Billing Worker",
        description: "Python APIs and Celery workers for billing, invoices, and scheduled jobs.",
        integration_kind: "python"
      ),
      web_frontend: upsert_project!(
        owner: users.fetch(:bob),
        slug: "web-frontend",
        name: "Web Frontend",
        description: "JavaScript and TypeScript app with client-side errors, logs, and release tracking.",
        integration_kind: "javascript"
      ),
      legacy_cfml: upsert_project!(
        owner: users.fetch(:carol),
        slug: "legacy-cfml",
        name: "Legacy CFML",
        description: "Lucee and Adobe ColdFusion app posting structured events over HTTP.",
        integration_kind: "cfml"
      ),
      dotnet_api: upsert_project!(
        owner: users.fetch(:bob),
        slug: "dotnet-api",
        name: ".NET API",
        description: "ASP.NET Core APIs, background services, and queue workers sending errors, logs, metrics, transactions, and spans.",
        integration_kind: "dotnet"
      )
    }
  end

  def seed_memberships(users, projects)
    membership!(user: users.fetch(:bob), project: projects.fetch(:storefront))
    membership!(user: users.fetch(:carol), project: projects.fetch(:storefront))
    membership!(user: users.fetch(:alice), project: projects.fetch(:web_frontend))
    membership!(user: users.fetch(:bob), project: projects.fetch(:billing_worker))
    membership!(user: users.fetch(:carol), project: projects.fetch(:web_frontend))
    membership!(user: users.fetch(:alice), project: projects.fetch(:dotnet_api))
    membership!(user: users.fetch(:carol), project: projects.fetch(:dotnet_api))
  end

  def seed_api_keys(projects)
    {
      storefront_primary: upsert_api_key!(
        project: projects.fetch(:storefront),
        user: projects.fetch(:storefront).user,
        name: "Primary ingest key",
        token: "seed-storefront-primary"
      ),
      storefront_revoked: upsert_api_key!(
        project: projects.fetch(:storefront),
        user: projects.fetch(:storefront).user,
        name: "Legacy key (revoked)",
        token: "seed-storefront-revoked",
        revoked: true
      ),
      billing_primary: upsert_api_key!(
        project: projects.fetch(:billing_worker),
        user: projects.fetch(:billing_worker).user,
        name: "Primary ingest key",
        token: "seed-billing-primary"
      ),
      web_primary: upsert_api_key!(
        project: projects.fetch(:web_frontend),
        user: projects.fetch(:web_frontend).user,
        name: "Primary ingest key",
        token: "seed-web-primary"
      ),
      cfml_primary: upsert_api_key!(
        project: projects.fetch(:legacy_cfml),
        user: projects.fetch(:legacy_cfml).user,
        name: "Primary ingest key",
        token: "seed-cfml-primary"
      ),
      dotnet_primary: upsert_api_key!(
        project: projects.fetch(:dotnet_api),
        user: projects.fetch(:dotnet_api).user,
        name: "Primary ingest key",
        token: "seed-dotnet-primary"
      )
    }
  end

  def seed_events(projects, keys)
    now = Time.current.change(sec: 0)
    storefront = projects.fetch(:storefront)
    storefront_key = keys.fetch(:storefront_primary)
    billing = projects.fetch(:billing_worker)
    billing_key = keys.fetch(:billing_primary)
    web = projects.fetch(:web_frontend)
    web_key = keys.fetch(:web_primary)
    cfml = projects.fetch(:legacy_cfml)
    cfml_key = keys.fetch(:cfml_primary)
    dotnet = projects.fetch(:dotnet_api)
    dotnet_key = keys.fetch(:dotnet_primary)

    create_event!(
      project: storefront,
      api_key: storefront_key,
      key: "error-checkout-nomethod-1",
      event_type: :error,
      level: "error",
      message: "NoMethodError in CheckoutService",
      fingerprint: "checkout-nomethoderror",
      occurred_at: now - 5.days,
      context: error_context(release: "v1.4.0", env: "production", trace_id: "trace-checkout-1", request_id: "req-checkout-1")
    )
    create_event!(
      project: storefront,
      api_key: storefront_key,
      key: "error-checkout-nomethod-2",
      event_type: :error,
      level: "error",
      message: "NoMethodError in CheckoutService",
      fingerprint: "checkout-nomethoderror",
      occurred_at: now - 1.day - 3.hours,
      context: error_context(release: "v1.4.2", env: "production", trace_id: "trace-checkout-2", request_id: "req-checkout-2")
    )
    create_event!(
      project: storefront,
      api_key: storefront_key,
      key: "error-payments-timeout-1",
      event_type: :error,
      level: "error",
      message: "Net::ReadTimeout in PaymentsGateway",
      fingerprint: "payments-timeout",
      occurred_at: now - 2.hours,
      context: error_context(release: "v1.5.0", env: "production", trace_id: "trace-payments-1", request_id: "req-payments-1")
    )
    create_event!(
      project: storefront,
      api_key: storefront_key,
      key: "error-payments-timeout-2",
      event_type: :error,
      level: "error",
      message: "Net::ReadTimeout in PaymentsGateway",
      fingerprint: "payments-timeout",
      occurred_at: now - 45.minutes,
      context: error_context(release: "v1.5.0", env: "production", trace_id: "trace-payments-2", request_id: "req-payments-2")
    )
    create_event!(
      project: storefront,
      api_key: storefront_key,
      key: "error-inventory-deadlock",
      event_type: :error,
      level: "fatal",
      message: "ActiveRecord::Deadlocked in InventoryWorker",
      fingerprint: "inventory-deadlock",
      occurred_at: now - 3.days - 2.hours,
      context: error_context(release: "v1.4.1", env: "production")
    )
    create_event!(
      project: storefront,
      api_key: storefront_key,
      key: "error-search-nil",
      event_type: :error,
      level: "error",
      message: "undefined method `[]' for nil:NilClass",
      fingerprint: "search-nilclass",
      occurred_at: now - 2.days - 1.hour,
      context: error_context(release: "v1.4.3", env: "staging")
    )
    create_event!(
      project: storefront,
      api_key: storefront_key,
      key: "error-notifications-500",
      event_type: :error,
      level: "error",
      message: "External notification provider returned 500",
      fingerprint: "notifications-provider-500",
      occurred_at: now - 8.days,
      context: error_context(release: "v1.3.9", env: "production")
    )

    [ 120.5, 95.4, 310.2, 460.0, 220.4, 540.8, 88.0, 135.3 ].each_with_index do |duration, i|
      create_event!(
        project: storefront,
        api_key: storefront_key,
        key: "transaction-checkout-#{i + 1}",
        event_type: :transaction,
        level: i.even? ? "info" : "error",
        message: "checkout.process",
        occurred_at: now - (i * 25).minutes,
        context: {
          "transaction_name" => "CheckoutController#create",
          "duration_ms" => duration,
          "status" => (i.even? ? 200 : 500),
          "trace_id" => "trace-payments-2",
          "request_id" => "req-payments-2",
          "environment" => "production"
        }
      )
    end

    [ 18.2, 25.8, 42.1, 75.0, 210.7, 32.9 ].each_with_index do |duration, i|
      create_event!(
        project: storefront,
        api_key: storefront_key,
        key: "db-query-#{i + 1}",
        event_type: :metric,
        level: "info",
        message: "db.query",
        occurred_at: now - (i * 10).minutes - 3.minutes,
        context: {
          "duration_ms" => duration,
          "name" => "Product load",
          "sql" => "SELECT * FROM products WHERE id = ?",
          "environment" => "production"
        }
      )
    end

    [
      [ "checkout.queue_depth", 8, "count" ],
      [ "checkout.queue_depth", 22, "count" ],
      [ "checkout.cart_total", 148.25, "usd" ],
      [ "checkout.cart_total", 92.10, "usd" ],
      [ "cache.hit_rate", 0.94, "ratio" ]
    ].each_with_index do |(name, value, unit), i|
      create_event!(
        project: storefront,
        api_key: storefront_key,
        key: "custom-metric-#{i + 1}",
        event_type: :metric,
        level: "info",
        message: name,
        occurred_at: now - (i * 17).minutes - 7.minutes,
        context: {
          "value" => value,
          "unit" => unit,
          "environment" => "production",
          "release" => "v1.5.0"
        }
      )
    end

    [ -4, -2, 1 ].each_with_index do |minute_offset, i|
      create_event!(
        project: storefront,
        api_key: storefront_key,
        key: "related-log-#{i + 1}",
        event_type: :log,
        level: i == 1 ? "warn" : "info",
        message: i == 1 ? "Payment retry triggered" : "Checkout request breadcrumb",
        occurred_at: now - 45.minutes + minute_offset.minutes,
        context: {
          "trace_id" => "trace-payments-2",
          "request_id" => "req-payments-2",
          "session_id" => "session-42",
          "user_id" => "user-42",
          "environment" => "production"
        }
      )
    end

    create_event!(
      project: storefront,
      api_key: storefront_key,
      key: "checkin-fulfillment-ok",
      event_type: :check_in,
      level: "info",
      message: "fulfillment-sync",
      occurred_at: now - 4.minutes,
      context: check_in_context(status: "ok", slug: "fulfillment-sync", expected_interval_seconds: 300, env: "production")
    )
    create_event!(
      project: storefront,
      api_key: storefront_key,
      key: "checkin-billing-missed",
      event_type: :check_in,
      level: "info",
      message: "billing-rollup",
      occurred_at: now - 2.hours,
      context: check_in_context(status: "ok", slug: "billing-rollup", expected_interval_seconds: 300, env: "production")
    )
    create_event!(
      project: storefront,
      api_key: storefront_key,
      key: "checkin-notifier-error",
      event_type: :check_in,
      level: "error",
      message: "notifier-heartbeat",
      occurred_at: now - 15.minutes,
      context: check_in_context(status: "error", slug: "notifier-heartbeat", expected_interval_seconds: 600, env: "production")
    )

    create_event!(
      project: billing,
      api_key: billing_key,
      key: "billing-error",
      event_type: :error,
      level: "error",
      message: "ValueError: invalid invoice state",
      fingerprint: "invoice-ratelimit",
      occurred_at: now - 90.minutes,
      context: python_error_context(
        release: "billing@2026.04.22",
        env: "production",
        framework: "celery",
        route: "/internal/invoices",
        request_id: "req-python-seed-1",
        trace_id: "trace-python-seed-1"
      )
    )
    create_event!(
      project: billing,
      api_key: billing_key,
      key: "billing-log",
      event_type: :log,
      level: "warning",
      message: "Retry queue backlog rising",
      occurred_at: now - 25.minutes,
      context: python_log_context(
        release: "billing@2026.04.22",
        framework: "celery",
        task_name: "billing.retry_failed_invoices",
        task_id: "task-seed-123"
      )
    )

    create_event!(
      project: billing,
      api_key: billing_key,
      key: "billing-checkin",
      event_type: :check_in,
      level: "info",
      message: "daily-billing-rollup",
      occurred_at: now - 8.minutes,
      context: check_in_context(status: "ok", slug: "daily-billing-rollup", expected_interval_seconds: 600, env: "production")
    )

    create_event!(
      project: web,
      api_key: web_key,
      key: "web-error",
      event_type: :error,
      level: "error",
      message: "TypeError: Cannot read properties of undefined",
      fingerprint: "javascript-typeerror-checkout",
      occurred_at: now - 35.minutes,
      context: javascript_error_context(release: "web@2026.04.22", route: "/checkout")
    )
    create_event!(
      project: web,
      api_key: web_key,
      key: "web-log",
      event_type: :log,
      level: "warning",
      message: "Queue backlog rising",
      occurred_at: now - 20.minutes,
      context: javascript_log_context(release: "web@2026.04.22", route: "/jobs/email-drain")
    )
    create_event!(
      project: web,
      api_key: web_key,
      key: "web-transaction",
      event_type: :transaction,
      level: "info",
      message: "checkout.submit",
      occurred_at: now - 12.minutes,
      context: {
        "transaction_name" => "CheckoutView#submit",
        "duration_ms" => 245.7,
        "status" => 200,
        "environment" => "production",
        "release" => "web@2026.04.22"
      }
    )

    create_event!(
      project: cfml,
      api_key: cfml_key,
      key: "cfml-error",
      event_type: :error,
      level: "error",
      message: "ColdFusion exception",
      fingerprint: "cfml-customer-undefined",
      occurred_at: now - 50.minutes,
      context: cfml_error_context(release: "cfml@2026.04.22", env: "production")
    )
    create_event!(
      project: cfml,
      api_key: cfml_key,
      key: "cfml-log",
      event_type: :log,
      level: "info",
      message: "Customer export completed",
      occurred_at: now - 20.minutes,
      context: {
        "environment" => "production",
        "request_id" => "req-cfml-1",
        "route" => "/reports/customer-export"
      }
    )

    create_event!(
      project: dotnet,
      api_key: dotnet_key,
      key: "dotnet-error",
      event_type: :error,
      level: "error",
      message: "InvalidOperationException in ApprovalController",
      fingerprint: "dotnet-approval-invalid-state",
      occurred_at: now - 40.minutes,
      context: dotnet_error_context(
        release: "api@2026.05.23",
        env: "production",
        route: "/api/approvals",
        request_id: "req-dotnet-seed-1",
        trace_id: "trace-dotnet-approval-1"
      )
    )
    create_event!(
      project: dotnet,
      api_key: dotnet_key,
      key: "dotnet-log",
      event_type: :log,
      level: "warning",
      message: "Approval queue backlog rising",
      occurred_at: now - 32.minutes,
      context: dotnet_log_context(
        release: "api@2026.05.23",
        category: "Logister.Sample.ApprovalWorker",
        event_id: 42,
        trace_id: "trace-dotnet-approval-1",
        request_id: "req-dotnet-seed-1"
      )
    )
    create_event!(
      project: dotnet,
      api_key: dotnet_key,
      key: "dotnet-transaction",
      event_type: :transaction,
      level: "info",
      message: "approvals.create",
      occurred_at: now - 31.minutes,
      context: {
        "transaction_name" => "ApprovalController#create",
        "duration_ms" => 382.6,
        "status" => 202,
        "trace_id" => "trace-dotnet-approval-1",
        "request_id" => "req-dotnet-seed-1",
        "environment" => "production",
        "release" => "api@2026.05.23"
      }
    )
    create_event!(
      project: dotnet,
      api_key: dotnet_key,
      key: "dotnet-metric-heap",
      event_type: :metric,
      level: "info",
      message: "dotnet.gc.heap_mb",
      occurred_at: now - 30.minutes,
      context: {
        "value" => 184.5,
        "unit" => "megabytes",
        "environment" => "production",
        "release" => "api@2026.05.23"
      }
    )
    create_event!(
      project: dotnet,
      api_key: dotnet_key,
      key: "dotnet-checkin-worker",
      event_type: :check_in,
      level: "info",
      message: "approval-worker",
      occurred_at: now - 6.minutes,
      context: check_in_context(status: "ok", slug: "approval-worker", expected_interval_seconds: 300, env: "production")
    )
  end

  def seed_trace_spans(projects, keys)
    now = Time.current.change(sec: 0)
    storefront = projects.fetch(:storefront)
    storefront_key = keys.fetch(:storefront_primary)
    web = projects.fetch(:web_frontend)
    web_key = keys.fetch(:web_primary)
    dotnet = projects.fetch(:dotnet_api)
    dotnet_key = keys.fetch(:dotnet_primary)

    checkout_started_at = now - 45.minutes - 5.seconds
    create_trace_span!(
      project: storefront,
      api_key: storefront_key,
      key: "storefront-checkout-root",
      trace_id: "trace-payments-2",
      span_id: "span-checkout-root",
      name: "POST /checkout",
      kind: "server",
      status: "error",
      duration_ms: 620.4,
      started_at: checkout_started_at,
      context: trace_context(
        service: "storefront",
        route: "/checkout",
        transaction_name: "CheckoutController#create",
        request_id: "req-payments-2",
        release: "v1.5.0",
        env: "production"
      )
    )
    create_trace_span!(
      project: storefront,
      api_key: storefront_key,
      key: "storefront-checkout-db",
      trace_id: "trace-payments-2",
      span_id: "span-checkout-db",
      parent_span_id: "span-checkout-root",
      name: "SELECT products",
      kind: "db",
      status: "ok",
      duration_ms: 210.7,
      started_at: checkout_started_at + 0.040.seconds,
      context: trace_context(
        service: "storefront",
        route: "/checkout",
        request_id: "req-payments-2",
        release: "v1.5.0",
        env: "production",
        extra: {
          "db.system" => "postgresql",
          "db.statement" => "SELECT * FROM products WHERE id = ?"
        }
      )
    )
    create_trace_span!(
      project: storefront,
      api_key: storefront_key,
      key: "storefront-checkout-http",
      trace_id: "trace-payments-2",
      span_id: "span-checkout-http",
      parent_span_id: "span-checkout-root",
      name: "POST payments.example.com/charge",
      kind: "http",
      status: "error",
      duration_ms: 320.2,
      started_at: checkout_started_at + 0.270.seconds,
      context: trace_context(
        service: "storefront",
        route: "/checkout",
        request_id: "req-payments-2",
        release: "v1.5.0",
        env: "production",
        extra: {
          "http.method" => "POST",
          "http.url" => "https://payments.example.com/charge",
          "http.status_code" => 504
        }
      )
    )
    create_trace_span!(
      project: storefront,
      api_key: storefront_key,
      key: "storefront-checkout-queue",
      trace_id: "trace-payments-2",
      span_id: "span-checkout-queue",
      parent_span_id: "span-checkout-root",
      name: "Enqueue FulfillmentJob",
      kind: "queue",
      status: "ok",
      duration_ms: 18.6,
      started_at: checkout_started_at + 0.590.seconds,
      context: trace_context(
        service: "storefront",
        route: "/checkout",
        request_id: "req-payments-2",
        release: "v1.5.0",
        env: "production",
        extra: { "messaging.destination" => "fulfillment" }
      )
    )

    browser_started_at = now - 12.minutes - 2.seconds
    create_trace_span!(
      project: web,
      api_key: web_key,
      key: "web-checkout-browser-root",
      trace_id: "trace-web-checkout-1",
      span_id: "span-web-browser-root",
      name: "CheckoutView#submit",
      kind: "browser",
      status: "ok",
      duration_ms: 245.7,
      started_at: browser_started_at,
      context: trace_context(
        service: "web-frontend",
        route: "/checkout",
        transaction_name: "CheckoutView#submit",
        request_id: "req-web-checkout-1",
        release: "web@2026.04.22",
        env: "production",
        extra: { "browser" => "Chrome 135" }
      )
    )
    create_trace_span!(
      project: web,
      api_key: web_key,
      key: "web-checkout-resource",
      trace_id: "trace-web-checkout-1",
      span_id: "span-web-resource",
      parent_span_id: "span-web-browser-root",
      name: "GET /assets/checkout.js",
      kind: "resource",
      status: "ok",
      duration_ms: 42.3,
      started_at: browser_started_at + 0.020.seconds,
      context: trace_context(
        service: "web-frontend",
        route: "/checkout",
        request_id: "req-web-checkout-1",
        release: "web@2026.04.22",
        env: "production"
      )
    )

    dotnet_started_at = now - 31.minutes - 3.seconds
    create_trace_span!(
      project: dotnet,
      api_key: dotnet_key,
      key: "dotnet-approval-root",
      trace_id: "trace-dotnet-approval-1",
      span_id: "span-dotnet-root",
      name: "POST /api/approvals",
      kind: "server",
      status: "ok",
      duration_ms: 382.6,
      started_at: dotnet_started_at,
      context: trace_context(
        service: "dotnet-api",
        route: "/api/approvals",
        transaction_name: "ApprovalController#create",
        request_id: "req-dotnet-seed-1",
        release: "api@2026.05.23",
        env: "production"
      )
    )
    create_trace_span!(
      project: dotnet,
      api_key: dotnet_key,
      key: "dotnet-approval-cache",
      trace_id: "trace-dotnet-approval-1",
      span_id: "span-dotnet-cache",
      parent_span_id: "span-dotnet-root",
      name: "GET approval-policy",
      kind: "cache",
      status: "ok",
      duration_ms: 12.4,
      started_at: dotnet_started_at + 0.035.seconds,
      context: trace_context(
        service: "dotnet-api",
        route: "/api/approvals",
        request_id: "req-dotnet-seed-1",
        release: "api@2026.05.23",
        env: "production",
        extra: { "cache.key" => "approval-policy" }
      )
    )
    create_trace_span!(
      project: dotnet,
      api_key: dotnet_key,
      key: "dotnet-approval-render",
      trace_id: "trace-dotnet-approval-1",
      span_id: "span-dotnet-render",
      parent_span_id: "span-dotnet-root",
      name: "Serialize approval response",
      kind: "render",
      status: "ok",
      duration_ms: 24.8,
      started_at: dotnet_started_at + 0.320.seconds,
      context: trace_context(
        service: "dotnet-api",
        route: "/api/approvals",
        request_id: "req-dotnet-seed-1",
        release: "api@2026.05.23",
        env: "production"
      )
    )
  end

  def seed_group_states(project)
    mark_group_status!(project: project, fingerprint: "inventory-deadlock", target: :resolved)
    mark_group_status!(project: project, fingerprint: "search-nilclass", target: :ignored)
    mark_group_status!(project: project, fingerprint: "notifications-provider-500", target: :archived)
  end

  def seed_retention_policies(projects)
    upsert_retention_policy!(
      project: projects.fetch(:storefront),
      hot_retention_days: 14,
      trace_retention_days: 14,
      error_retention_days: 180,
      archive_enabled: true,
      archive_before_delete: true
    )
    upsert_retention_policy!(
      project: projects.fetch(:billing_worker),
      hot_retention_days: 30,
      trace_retention_days: 30,
      error_retention_days: nil,
      archive_enabled: false,
      archive_before_delete: false
    )
    upsert_retention_policy!(
      project: projects.fetch(:dotnet_api),
      hot_retention_days: 60,
      trace_retention_days: 30,
      error_retention_days: 365,
      archive_enabled: true,
      archive_before_delete: false
    )
  end

  def seed_notification_preferences(users, projects)
    upsert_notification_preference!(
      user: users.fetch(:alice),
      project: projects.fetch(:storefront),
      first_occurrence_enabled: true,
      digest_frequency: "daily",
      digest_send_hour: 9,
      time_zone: "Eastern Time (US & Canada)",
      send_empty_digest: false
    )
    upsert_notification_preference!(
      user: users.fetch(:bob),
      project: projects.fetch(:storefront),
      first_occurrence_enabled: true,
      digest_frequency: "weekly",
      digest_send_hour: 10,
      time_zone: "UTC",
      send_empty_digest: false
    )
    upsert_notification_preference!(
      user: users.fetch(:carol),
      project: projects.fetch(:dotnet_api),
      first_occurrence_enabled: false,
      digest_frequency: "none",
      digest_send_hour: 8,
      time_zone: "Pacific Time (US & Canada)",
      send_empty_digest: false
    )
  end

  def seed_notification_deliveries(users, projects)
    storefront = projects.fetch(:storefront)
    payments_group = storefront.error_groups.find_by(fingerprint: "payments-timeout")
    return unless payments_group

    upsert_email_delivery!(
      user: users.fetch(:alice),
      project: storefront,
      error_group: payments_group,
      dedup_key: "seed:first_occurrence:alice:payments-timeout",
      notification_kind: "first_occurrence",
      status: "sent",
      sent_at: 40.minutes.ago,
      metadata: { "event_count" => payments_group.occurrence_count, "source" => "seed" }
    )
    upsert_email_delivery!(
      user: users.fetch(:bob),
      project: storefront,
      dedup_key: "seed:daily_digest:bob:storefront",
      notification_kind: "daily_digest",
      status: "sent",
      period_start_at: 1.day.ago.beginning_of_day,
      period_end_at: Time.current.beginning_of_day,
      sent_at: 2.hours.ago,
      metadata: { "groups" => 2, "events" => 12, "source" => "seed" }
    )
  end

  def seed_telemetry_archives(projects)
    upsert_telemetry_archive!(
      project: projects.fetch(:storefront),
      record_type: "ingest_events",
      scope: "hot_events",
      status: "completed",
      before_at: 30.days.ago,
      rows: 4_200,
      bytes: 1_850_000,
      objects: [
        {
          "bucket" => "logister-dev-archives",
          "key" => "storefront/hot-events/seed.jsonl.gz",
          "rows" => 4_200,
          "bytes" => 1_850_000
        }
      ]
    )
    upsert_telemetry_archive!(
      project: projects.fetch(:storefront),
      record_type: "trace_spans",
      scope: "trace_spans",
      status: "completed",
      before_at: 30.days.ago,
      rows: 980,
      bytes: 420_000,
      objects: [
        {
          "bucket" => "logister-dev-archives",
          "key" => "storefront/trace-spans/seed.jsonl.gz",
          "rows" => 980,
          "bytes" => 420_000
        }
      ]
    )
    upsert_telemetry_archive!(
      project: projects.fetch(:dotnet_api),
      record_type: "ingest_events",
      scope: "error_events",
      status: "failed",
      before_at: 90.days.ago,
      rows: 0,
      bytes: 0,
      error_message: "Seeded archive failure for local UI review"
    )
  end

  def upsert_user!(email, name)
    user = User.find_or_initialize_by(email: email)
    user.assign_attributes(
      name: name,
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: user.confirmed_at || Time.current,
      confirmation_token: nil,
      confirmation_sent_at: nil,
      unconfirmed_email: nil
    )
    user.save!
    user
  end

  def upsert_project!(owner:, slug:, name:, description:, integration_kind:)
    project = owner.projects.find_or_initialize_by(slug: slug)
    project.assign_attributes(name: name, description: description, integration_kind: integration_kind)
    project.save!
    project
  end

  def membership!(user:, project:)
    ProjectMembership.find_or_create_by!(user: user, project: project)
  end

  def upsert_api_key!(project:, user:, name:, token:, revoked: false)
    key = project.api_keys.find_or_initialize_by(name: name)
    key.assign_attributes(
      user: user,
      token_digest: ApiKey.digest(token),
      last_used_at: Time.current - 10.minutes
    )
    key.revoked_at = revoked ? (key.revoked_at || Time.current - 1.day) : nil
    key.save!
    key
  end

  def create_event!(project:, api_key:, key:, event_type:, message:, occurred_at:, level:, context:, fingerprint: nil)
    event = project.ingest_events.find_or_initialize_by(uuid: stable_uuid("event/#{project.slug}/#{key}"))
    created = event.new_record?

    event.assign_attributes(
      api_key: api_key,
      event_type: event_type,
      level: level,
      message: message,
      fingerprint: fingerprint,
      occurred_at: occurred_at,
      context: context
    )
    event.save!

    if created || (event.error? && event.error_group_id.nil?)
      ErrorGroupingService.call(event)
    end
    if event.check_in? && (created || missing_monitor_for?(project, event))
      CheckInMonitor.record!(project: project, event: event)
    end

    event
  end

  def cleanup_non_check_in_monitors(projects)
    CheckInMonitor
      .joins(:last_event)
      .where(project_id: projects.values.map(&:id))
      .where.not(ingest_events: { event_type: IngestEvent.event_types[:check_in] })
      .destroy_all
  end

  def create_trace_span!(project:, api_key:, key:, trace_id:, span_id:, name:, kind:, status:, duration_ms:, started_at:, context:, parent_span_id: nil)
    span = project.trace_spans.find_or_initialize_by(trace_id: trace_id, span_id: span_id)
    span.uuid ||= stable_uuid("trace-span/#{project.slug}/#{key}")
    span.assign_attributes(
      api_key: api_key,
      parent_span_id: parent_span_id,
      name: name,
      kind: kind,
      status: status,
      duration_ms: duration_ms,
      started_at: started_at,
      ended_at: nil,
      context: context
    )
    span.save!
    span
  end

  def upsert_retention_policy!(project:, hot_retention_days:, trace_retention_days:, error_retention_days:, archive_enabled:, archive_before_delete:)
    policy = ProjectRetentionPolicy.for(project: project)
    policy.update!(
      hot_retention_days: hot_retention_days,
      trace_retention_days: trace_retention_days,
      error_retention_days: error_retention_days,
      archive_enabled: archive_enabled,
      archive_before_delete: archive_before_delete,
      last_retention_run_at: 1.hour.ago,
      last_archive_run_at: archive_enabled ? 2.hours.ago : nil,
      last_retention_result: {
        "candidates" => { "hot_events" => 42, "trace_spans" => 12, "closed_error_groups" => 1 },
        "deleted" => { "hot_events" => 0, "trace_spans" => 0, "closed_error_groups" => 0 },
        "seeded" => true
      }
    )
    policy
  end

  def upsert_notification_preference!(user:, project:, first_occurrence_enabled:, digest_frequency:, digest_send_hour:, time_zone:, send_empty_digest:)
    preference = ProjectNotificationPreference.for(user: user, project: project)
    preference.update!(
      first_occurrence_enabled: first_occurrence_enabled,
      digest_frequency: digest_frequency,
      digest_send_hour: digest_send_hour,
      time_zone: time_zone,
      send_empty_digest: send_empty_digest
    )
    preference
  end

  def upsert_email_delivery!(user:, project:, dedup_key:, notification_kind:, status:, metadata:, error_group: nil, period_start_at: nil, period_end_at: nil, sent_at: nil)
    delivery = EmailNotificationDelivery.find_or_initialize_by(dedup_key: dedup_key)
    delivery.uuid ||= stable_uuid("email-delivery/#{dedup_key}")
    delivery.assign_attributes(
      user: user,
      project: project,
      error_group: error_group,
      notification_kind: notification_kind,
      status: status,
      period_start_at: period_start_at,
      period_end_at: period_end_at,
      sent_at: sent_at,
      last_error: nil,
      metadata: metadata
    )
    delivery.save!
    delivery
  end

  def upsert_telemetry_archive!(project:, record_type:, scope:, status:, before_at:, rows:, bytes:, objects: [], error_message: nil)
    archive = project.telemetry_archives.find_or_initialize_by(record_type: record_type, scope: scope)
    archive.assign_attributes(
      status: status,
      before_at: before_at,
      after_at: before_at - 30.days,
      rows: rows,
      bytes: bytes,
      objects: objects,
      error_message: error_message,
      dry_run: false
    )
    archive.save!
    archive
  end

  def missing_monitor_for?(project, event)
    payload = CheckInMonitor.extract_check_in_payload(event)
    !project.check_in_monitors.exists?(slug: payload[:slug], environment: payload[:environment])
  end

  def mark_group_status!(project:, fingerprint:, target:)
    group = project.error_groups.find_by(fingerprint: fingerprint)
    return unless group
    return if group.status.to_sym == target

    case target
    when :resolved then group.mark_resolved!
    when :ignored then group.ignore!
    when :archived then group.archive!
    when :unresolved then group.reopen!
    end
  end

  def stable_uuid(key)
    hex = Digest::SHA256.hexdigest("logister-seed:#{key}")[0, 32]
    "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
  end

  def error_context(release:, env:, trace_id: nil, request_id: nil)
    {
      "environment" => env,
      "release" => release,
      "trace_id" => trace_id,
      "request_id" => request_id,
      "exception" => {
        "class" => "RuntimeError",
        "message" => "Seeded failure for development"
      }
    }.compact
  end

  def check_in_context(status:, slug:, expected_interval_seconds:, env:)
    {
      "environment" => env,
      "check_in_slug" => slug,
      "check_in_status" => status,
      "expected_interval_seconds" => expected_interval_seconds
    }
  end

  def trace_context(service:, route:, request_id:, release:, env:, transaction_name: nil, extra: {})
    {
      "service" => service,
      "route" => route,
      "http.route" => route,
      "transaction_name" => transaction_name,
      "request_id" => request_id,
      "release" => release,
      "environment" => env
    }.compact.merge(extra)
  end

  def dotnet_error_context(release:, env:, route:, request_id:, trace_id:)
    {
      "environment" => env,
      "release" => release,
      "runtime" => "dotnet",
      "framework" => "ASP.NET Core",
      "dotnet_version" => "8.0.11",
      "service" => "dotnet-api",
      "route" => route,
      "trace_id" => trace_id,
      "request_id" => request_id,
      "request" => {
        "method" => "POST",
        "url" => "https://api.example.com#{route}",
        "request_id" => request_id,
        "client_ip" => "203.0.113.42"
      },
      "exception" => {
        "class" => "InvalidOperationException",
        "qualified_class" => "System.InvalidOperationException",
        "message" => "Approval cannot be submitted from the current state.",
        "frames" => [
          {
            "filename" => "/src/ApprovalController.cs",
            "lineno" => 87,
            "name" => "Create",
            "line" => "throw new InvalidOperationException(\"Approval cannot be submitted from the current state.\");"
          },
          {
            "filename" => "/src/ApprovalService.cs",
            "lineno" => 42,
            "name" => "SubmitAsync",
            "line" => "await workflow.SubmitAsync(approval);"
          }
        ],
        "backtrace" => [
          "at Logister.Sample.ApprovalController.Create() in /src/ApprovalController.cs:line 87",
          "at Logister.Sample.ApprovalService.SubmitAsync() in /src/ApprovalService.cs:line 42"
        ]
      }
    }
  end

  def dotnet_log_context(release:, category:, event_id:, trace_id:, request_id:)
    {
      "environment" => "production",
      "release" => release,
      "runtime" => "dotnet",
      "framework" => "Worker Service",
      "trace_id" => trace_id,
      "request_id" => request_id,
      "logger_name" => category,
      "logger" => {
        "category" => category,
        "event_id" => event_id,
        "event_name" => "ApprovalBacklogRising"
      },
      "log_record" => {
        "queue" => "approvals",
        "backlog" => 128,
        "worker" => "approval-worker-1"
      }
    }
  end

  def python_error_context(release:, env:, framework:, route:, request_id:, trace_id:)
    {
      "environment" => env,
      "release" => release,
      "framework" => framework,
      "runtime" => "python",
      "python_version" => "3.12.3",
      "python_implementation" => "CPython",
      "platform" => "macOS-14.0-arm64",
      "hostname" => "worker-1",
      "process_id" => 4242,
      "route" => route,
      "request" => {
        "method" => "POST",
        "request_id" => request_id,
        "url" => "https://api.example.com#{route}",
        "client_ip" => "203.0.113.8"
      },
      "trace_id" => trace_id,
      "exception" => {
        "class" => "ValueError",
        "qualified_class" => "builtins.ValueError",
        "message" => "invalid invoice state",
        "frames" => [
          {
            "filename" => "/srv/app/billing/invoice_job.py",
            "lineno" => 41,
            "name" => "generate_invoice",
            "line" => "raise ValueError('invalid invoice state')",
            "locals" => { "invoice_id" => "inv_123" }
          }
        ],
        "cause" => {
          "class" => "KeyError",
          "message" => "customer_id",
          "frames" => [
            {
              "filename" => "/srv/app/billing/customer_lookup.py",
              "lineno" => 12,
              "name" => "fetch_customer",
              "line" => "raise KeyError('customer_id')"
            }
          ]
        },
        "backtrace" => [
          "File \"/srv/app/billing/invoice_job.py\", line 41, in generate_invoice"
        ]
      }
    }
  end

  def python_log_context(release:, framework:, task_name:, task_id:)
    {
      "logger_name" => "billing.retry",
      "logger" => {
        "name" => "billing.retry",
        "module" => "billing.retry_worker",
        "pathname" => "/srv/app/billing/retry_worker.py",
        "filename" => "retry_worker.py",
        "function" => "drain_retry_queue",
        "line_number" => 88,
        "process" => 7021,
        "thread" => 19
      },
      "log_record" => {
        "request_id" => "req-log-1",
        "trace_id" => "trace-log-1",
        "queue" => "billing",
        "retry_count" => 4
      },
      "framework" => framework,
      "runtime" => "python",
      "python_version" => "3.12.3",
      "hostname" => "worker-2",
      "process_id" => 7021,
      "release" => release,
      "task_name" => task_name,
      "task_id" => task_id,
      "task_module" => "billing.tasks"
    }
  end

  def javascript_error_context(release:, route:)
    {
      "browser" => "Chrome 135",
      "os" => "macOS",
      "route" => route,
      "release" => release,
      "user_agent" => "Mozilla/5.0",
      "breadcrumbs" => [
        { "category" => "ui.click", "message" => "Clicked checkout button" }
      ],
      "exception" => {
        "class" => "TypeError",
        "message" => "Cannot read properties of undefined",
        "frames" => [
          {
            "filename" => "https://app.example.com/assets/app.min.js",
            "lineno" => 2,
            "colno" => 1450,
            "name" => "renderCheckout"
          },
          {
            "filename" => "https://app.example.com/assets/app.min.js",
            "lineno" => 9,
            "colno" => 321,
            "name" => "onSubmit"
          }
        ],
        "backtrace" => [
          "at renderCheckout (https://app.example.com/assets/app.min.js:2:1450)",
          "at onSubmit (https://app.example.com/assets/app.min.js:9:321)"
        ],
        "stack" => "TypeError: Cannot read properties of undefined\n    at renderCheckout (https://app.example.com/assets/app.min.js:2:1450)\n    at onSubmit (https://app.example.com/assets/app.min.js:9:321)\n",
        "cause" => {
          "class" => "Error",
          "message" => "checkout state missing",
          "frames" => [
            {
              "filename" => "https://app.example.com/src/lib/checkout.ts",
              "lineno" => 27,
              "colno" => 14,
              "name" => "validateCheckout"
            }
          ]
        }
      }
    }
  end

  def javascript_log_context(release:, route:)
    {
      "logger_name" => "console",
      "logger" => {
        "name" => "console",
        "method" => "warn",
        "filename" => "worker.js",
        "function" => "flushQueue"
      },
      "log_record" => {
        "arguments" => [ "Queue backlog rising", { "queue" => "emails" } ],
        "original_method" => "warn"
      },
      "runtime" => "node",
      "route" => route,
      "release" => release,
      "url" => "https://app.example.com#{route}"
    }
  end

  def cfml_error_context(release:, env:)
    {
      "environment" => env,
      "release" => release,
      "exception" => {
        "type" => "Expression",
        "message" => "Variable CUSTOMER is undefined.",
        "template" => "/srv/www/app/orders/show.cfm",
        "line" => 118,
        "detail" => "The error occurred while rendering the order details template."
      },
      "template_frames" => [
        {
          "template" => "/srv/www/app/orders/show.cfm",
          "line" => 118,
          "code" => "<cfset customerName = CUSTOMER.name>"
        },
        {
          "template" => "/srv/www/app/layouts/application.cfm",
          "line" => 52,
          "code" => "<cfinclude template=\"/orders/show.cfm\">"
        }
      ],
      "request" => {
        "method" => "GET",
        "url" => "https://legacy.example.com/orders/show.cfm?id=42",
        "request_id" => "req-cfml-seed-1"
      }
    }
  end
end

Seeds.run!

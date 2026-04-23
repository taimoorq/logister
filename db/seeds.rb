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
    seed_group_states(projects.fetch(:storefront))

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
      )
    }
  end

  def seed_memberships(users, projects)
    membership!(user: users.fetch(:bob), project: projects.fetch(:storefront))
    membership!(user: users.fetch(:carol), project: projects.fetch(:storefront))
    membership!(user: users.fetch(:alice), project: projects.fetch(:web_frontend))
    membership!(user: users.fetch(:bob), project: projects.fetch(:billing_worker))
    membership!(user: users.fetch(:carol), project: projects.fetch(:web_frontend))
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
      context: { "environment" => "production", "request_id" => "req-cfml-1", "route" => "/reports/customer-export" }
    )
  end

  def seed_group_states(project)
    mark_group_status!(project: project, fingerprint: "inventory-deadlock", target: :resolved)
    mark_group_status!(project: project, fingerprint: "search-nilclass", target: :ignored)
    mark_group_status!(project: project, fingerprint: "notifications-provider-500", target: :archived)
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
    if created || (event.check_in? && missing_monitor_for?(project, event))
      CheckInMonitor.record!(project: project, event: event)
    end

    event
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

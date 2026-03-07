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
        description: "Rails storefront app with checkout, search, and background jobs."
      ),
      billing_api: upsert_project!(
        owner: users.fetch(:alice),
        slug: "billing-api",
        name: "Billing API",
        description: "Internal billing API and recurring invoice workers."
      ),
      mobile_backend: upsert_project!(
        owner: users.fetch(:bob),
        slug: "mobile-backend",
        name: "Mobile Backend",
        description: "Backend APIs and auth services for mobile clients."
      )
    }
  end

  def seed_memberships(users, projects)
    membership!(user: users.fetch(:bob), project: projects.fetch(:storefront))
    membership!(user: users.fetch(:carol), project: projects.fetch(:storefront))
    membership!(user: users.fetch(:alice), project: projects.fetch(:mobile_backend))
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
        project: projects.fetch(:billing_api),
        user: projects.fetch(:billing_api).user,
        name: "Primary ingest key",
        token: "seed-billing-primary"
      ),
      mobile_primary: upsert_api_key!(
        project: projects.fetch(:mobile_backend),
        user: projects.fetch(:mobile_backend).user,
        name: "Primary ingest key",
        token: "seed-mobile-primary"
      )
    }
  end

  def seed_events(projects, keys)
    now = Time.current.change(sec: 0)
    storefront = projects.fetch(:storefront)
    storefront_key = keys.fetch(:storefront_primary)
    billing = projects.fetch(:billing_api)
    billing_key = keys.fetch(:billing_primary)
    mobile = projects.fetch(:mobile_backend)
    mobile_key = keys.fetch(:mobile_primary)

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
      message: "Stripe::RateLimitError in InvoiceJob",
      fingerprint: "invoice-ratelimit",
      occurred_at: now - 90.minutes,
      context: error_context(release: "v2.0.1", env: "production")
    )
    create_event!(
      project: billing,
      api_key: billing_key,
      key: "billing-transaction",
      event_type: :transaction,
      level: "info",
      message: "invoice.generate",
      occurred_at: now - 25.minutes,
      context: {
        "transaction_name" => "InvoiceJob#perform",
        "duration_ms" => 180.5,
        "status" => 200,
        "environment" => "production"
      }
    )

    create_event!(
      project: mobile,
      api_key: mobile_key,
      key: "mobile-log",
      event_type: :log,
      level: "info",
      message: "User login succeeded",
      occurred_at: now - 20.minutes,
      context: { "environment" => "production", "request_id" => "req-mobile-1" }
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

  def upsert_project!(owner:, slug:, name:, description:)
    project = owner.projects.find_or_initialize_by(slug: slug)
    project.assign_attributes(name: name, description: description)
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
end

Seeds.run!

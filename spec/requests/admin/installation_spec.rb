# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin installation", type: :request do
  let(:admin) { users(:one) }
  let(:installation) { Installation.current }

  before do
    admin.update!(application_admin: true)
    installation.claim!(admin)
    sign_in admin
    allow(InstanceConfiguration::Runtime).to receive(:apply!)
  end

  it "keeps every installation section available as a permanent admin path" do
    installation.update!(completed_at: Time.current)

    InstanceConfiguration::Registry.sections.each do |section|
      get admin_installation_section_path(section.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(section.label), section.description)
    end
  end

  it "guides administrators through core setup before optional add-ons" do
    get admin_installation_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Continue with General", "1. Finish the core install", "2. Add only what you need")
    expect(response.body).to include("Invite and notify people", "Scale and retain telemetry", "Connect source and protect access", "Operate the public instance")
    InstanceConfiguration::Registry.sections.each do |section|
      expect(response.body).to include(admin_installation_section_path(section.slug))
    end
  end

  it "accepts legacy underscore section URLs while advertising hyphenated paths" do
    get admin_installation_section_path("background_jobs")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('/admin/installation/background-jobs')
    expect(response.body).to include('data-turbo="false"')
  end

  it "shows an environment override without exposing a secret value" do
    original = ENV["REDIS_URL"]
    ENV["REDIS_URL"] = "rediss://user:environment-secret@redis.example/0"
    InstanceConfiguration.save_section!(
      "background_jobs",
      values: { "background_jobs.redis_url" => "redis://saved-fallback.example/0" },
      clear_keys: [],
      actor: admin
    )

    get admin_installation_section_path("background-jobs")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Environment override active", "REDIS_URL", "encrypted fallback is saved")
    expect(response.body).not_to include("environment-secret", "saved-fallback")
  ensure
    ENV["REDIS_URL"] = original
  end

  it "marks a previously verified section as changed when an environment override changes" do
    original = ENV["LOGISTER_PUBLIC_URL"]
    ENV.delete("LOGISTER_PUBLIC_URL")
    installation.step_for("general").mark_verified!(
      fingerprint: InstanceConfiguration.fingerprint("general"),
      user: admin,
      details: {}
    )
    ENV["LOGISTER_PUBLIC_URL"] = "https://changed.example.com"

    get admin_installation_section_path("general")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Environment override active", "LOGISTER_PUBLIC_URL", "Changed")
  ensure
    ENV["LOGISTER_PUBLIC_URL"] = original
  end

  it "saves editable fallback settings and records a redacted audit event" do
    patch admin_installation_section_path("authentication"), params: {
      settings: {
        "authentication.turnstile_enabled" => "1",
        "authentication.turnstile_site_key" => "site-key",
        "authentication.turnstile_secret_key" => "secret-key"
      }
    }

    expect(response).to redirect_to(admin_installation_section_path("authentication"))
    expect(InstanceConfiguration.value("authentication.turnstile_site_key")).to eq("site-key")
    expect(InstanceConfiguration.value("authentication.turnstile_secret_key")).to eq("secret-key")
    expect(InstanceSettingChange.where(key: "authentication.turnstile_secret_key").last.details.to_json).not_to include("secret-key")
    expect(installation.installation_steps.find_by!(key: "authentication")).to be_configured
  end

  it "tests candidate values and persists verification against their fingerprint" do
    result = InstanceConfiguration::Diagnostics::Result.new(
      success: true,
      summary: "Redis is reachable.",
      details: { "redis" => "reachable" }
    )
    allow(InstanceConfiguration::Diagnostics).to receive(:call).and_return(result)

    patch admin_test_installation_section_path("background-jobs"), params: {
      settings: {
        "background_jobs.redis_url" => "redis://candidate.example/0",
        "background_jobs.sidekiq_concurrency" => "7"
      }
    }

    step = installation.installation_steps.find_by!(key: "background_jobs")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Check passed", "Redis is reachable")
    expect(step).to be_verified
    expect(step.configuration_fingerprint).to eq(
      InstanceConfiguration.fingerprint(
        "background_jobs",
        overrides: {
          "background_jobs.redis_url" => "redis://candidate.example/0",
          "background_jobs.sidekiq_concurrency" => "7"
        }
      )
    )
  end

  it "requires SMTP changes to be saved before sending delivery tests" do
    expect(InstanceConfiguration::Diagnostics).not_to receive(:call)

    patch admin_test_installation_section_path("email"), params: {
      settings: { "email.smtp_address" => "smtp.candidate.example.com" },
      test_recipient: "operator@example.com"
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Save these SMTP settings")
  end

  it "blocks ClickHouse reads until the connection and coverage fingerprint is verified" do
    installation.step_for("clickhouse").mark_verified!(
      fingerprint: InstanceConfiguration.fingerprint("clickhouse"),
      user: admin,
      details: { "mode" => "disabled" }
    )

    patch admin_installation_section_path("clickhouse"), params: {
      settings: {
        "clickhouse.mode" => "read_preferred",
        "clickhouse.url" => "https://clickhouse.example.com"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("before switching reads to ClickHouse")
    expect(InstanceSetting.find_by(key: "clickhouse.mode")).to be_nil
  end

  it "allows read preferred after an enabled coverage check passes" do
    overrides = {
      "clickhouse.mode" => "dual_write",
      "clickhouse.url" => "https://clickhouse.example.com"
    }
    installation.step_for("clickhouse").mark_verified!(
      fingerprint: InstanceConfiguration.fingerprint("clickhouse", overrides: overrides),
      user: admin,
      details: { "ready_for_reads" => true }
    )

    patch admin_installation_section_path("clickhouse"), params: {
      settings: overrides.merge("clickhouse.mode" => "read_preferred")
    }

    expect(response).to redirect_to(admin_installation_section_path("clickhouse"))
    expect(InstanceConfiguration.value("clickhouse.mode")).to eq("read_preferred")
  end

  it "runs an explicit idempotent ClickHouse schema repair from the admin path" do
    allow(Logister::ClickhouseSchemaRepairer).to receive(:call).and_return(
      loaded_statements: 8,
      repaired_columns: [],
      rebuilt_views: [],
      schema: { ready: true }
    )

    post admin_repair_installation_section_path("clickhouse")

    expect(response).to redirect_to(admin_installation_section_path("clickhouse"))
    expect(Logister::ClickhouseSchemaRepairer).to have_received(:call)
    expect(InstanceSettingChange.where(key: "section.clickhouse").last).to have_attributes(action: "schema_repaired")
  end

  it "completes onboarding only after current required checks pass" do
    %w[general background_jobs].each do |key|
      installation.step_for(key).mark_verified!(
        fingerprint: InstanceConfiguration.fingerprint(key),
        user: admin,
        details: {}
      )
    end

    post complete_admin_installation_path

    expect(response).to redirect_to(dashboard_path)
    expect(installation.reload).to be_complete
  end
end

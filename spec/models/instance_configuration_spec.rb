# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstanceConfiguration, type: :model do
  around do |example|
    redis_keys = %w[REDIS_URL REDIS_CACHE_URL REDIS_RATE_LIMIT_URL REDIS_SIDEKIQ_URL]
    original = ENV.to_h.slice(*redis_keys)
    redis_keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    redis_keys.each { |key| ENV.delete(key) }
    original.each { |key, value| ENV[key] = value }
  end

  it "supports independent Redis roles with backward-compatible shared fallback" do
    ENV["REDIS_URL"] = "redis://shared.example/0"

    expect(described_class.redis_url(:cache)).to eq("redis://shared.example/0")
    expect(described_class.redis_url(:rate_limit)).to eq("redis://shared.example/0")
    expect(described_class.redis_url(:sidekiq)).to eq("redis://shared.example/0")

    ENV["REDIS_CACHE_URL"] = "redis://cache.example/0"
    ENV["REDIS_RATE_LIMIT_URL"] = "redis://rate-limit.example/0"
    ENV["REDIS_SIDEKIQ_URL"] = "redis://sidekiq.example/0"

    expect(described_class.redis_url(:cache)).to eq("redis://cache.example/0")
    expect(described_class.redis_url(:rate_limit)).to eq("redis://rate-limit.example/0")
    expect(described_class.redis_url(:sidekiq)).to eq("redis://sidekiq.example/0")
  end

  it "encrypts saved values and resolves database fallbacks" do
    described_class.save_section!(
      "background_jobs",
      values: { "background_jobs.redis_url" => "rediss://user:super-secret@redis.example/0" },
      clear_keys: [],
      actor: users(:one),
      request_id: "request-1"
    )

    setting = InstanceSetting.find_by!(key: "background_jobs.redis_url")
    expect(setting.encrypted_value).not_to include("super-secret")
    expect(described_class.value("background_jobs.redis_url")).to eq("rediss://user:super-secret@redis.example/0")
    expect(InstanceSettingChange.last.details).to include("secret" => true)
    expect(InstanceSettingChange.last.details.to_json).not_to include("super-secret")
  end

  it "keeps an environment value effective while retaining the saved fallback" do
    described_class.save_section!(
      "background_jobs",
      values: { "background_jobs.redis_url" => "redis://saved.example/0" },
      clear_keys: [],
      actor: users(:one)
    )
    ENV["REDIS_URL"] = "rediss://environment.example/0"

    entry = described_class.entry("background_jobs.redis_url")

    expect(entry.effective_value).to eq("rediss://environment.example/0")
    expect(entry.saved_value).to eq("redis://saved.example/0")
    expect(entry).to be_environment_override
  end

  it "falls back to defaults when the configuration database is unavailable" do
    allow(InstanceSetting).to receive(:find_by).and_raise(
      ActiveRecord::ConnectionNotEstablished,
      "database unavailable"
    )

    expect(described_class.value("clickhouse.mode")).to eq("disabled")
  end

  it "leaves a saved secret unchanged when a blank secret field is submitted" do
    described_class.save_section!(
      "background_jobs",
      values: { "background_jobs.redis_url" => "redis://saved.example/0" },
      clear_keys: [],
      actor: users(:one)
    )

    described_class.save_section!(
      "background_jobs",
      values: { "background_jobs.redis_url" => "" },
      clear_keys: [],
      actor: users(:one)
    )

    expect(described_class.value("background_jobs.redis_url")).to eq("redis://saved.example/0")
  end

  it "separates disabled ClickHouse verification from enabled cutover verification" do
    disabled = described_class.fingerprint("clickhouse", overrides: { "clickhouse.mode" => "disabled" })
    dual_write = described_class.fingerprint("clickhouse", overrides: { "clickhouse.mode" => "dual_write" })
    read_preferred = described_class.fingerprint("clickhouse", overrides: { "clickhouse.mode" => "read_preferred" })

    expect(disabled).not_to eq(dual_write)
    expect(dual_write).to eq(read_preferred)
  end
end

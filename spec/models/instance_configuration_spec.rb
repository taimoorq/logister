# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstanceConfiguration, type: :model do
  around do |example|
    original = ENV["REDIS_URL"]
    ENV.delete("REDIS_URL")
    example.run
  ensure
    ENV["REDIS_URL"] = original
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
end

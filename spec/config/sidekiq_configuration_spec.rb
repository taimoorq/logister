# frozen_string_literal: true

require "rails_helper"
require "sidekiq/cli"

RSpec.describe "Sidekiq configuration" do
  around do |example|
    previous = ENV.slice("SIDEKIQ_CONCURRENCY", "SIDEKIQ_PROJECTOR_CONCURRENCY")
    ENV.delete("SIDEKIQ_PROJECTOR_CONCURRENCY")
    example.run
  ensure
    %w[SIDEKIQ_CONCURRENCY SIDEKIQ_PROJECTOR_CONCURRENCY].each do |key|
      previous.key?(key) ? ENV[key] = previous[key] : ENV.delete(key)
    end
  end

  it "uses SIDEKIQ_CONCURRENCY as the combined-worker default" do
    ENV["SIDEKIQ_CONCURRENCY"] = "4"

    expect(parsed_concurrency("-C", Rails.root.join("config/sidekiq.yml").to_s)).to eq(4)
  end

  it "preserves an explicit Sidekiq CLI concurrency" do
    ENV["SIDEKIQ_CONCURRENCY"] = "4"

    expect(
      parsed_concurrency("-C", Rails.root.join("config/sidekiq.yml").to_s, "-c", "2")
    ).to eq(2)
  end

  it "keeps archive work isolated in the production worker profiles" do
    core = parsed_config("-C", Rails.root.join("config/sidekiq-core.yml").to_s)
    archives = parsed_config("-C", Rails.root.join("config/sidekiq-archives.yml").to_s)
    combined = parsed_config("-C", Rails.root.join("config/sidekiq.yml").to_s)

    expect(core.capsule("default").queues).not_to include("archives")
    expect(archives.capsule("default").queues).to eq([ "archives" ])
    expect(archives.concurrency).to eq(1)
    expect(combined.capsule("default").queues).to include("archives")
  end

  it "does not replace Sidekiq's parsed concurrency during Rails initialization" do
    initializer = Rails.root.join("config/initializers/sidekiq.rb").read

    expect(initializer).not_to match(/config\.concurrency\s*=/)
  end

  it "reserves general capacity within the parsed core concurrency budget" do
    ENV["SIDEKIQ_CONCURRENCY"] = "5"
    core = configured_core

    expect(core.total_concurrency).to eq(5)
    expect(core.default_capsule.concurrency).to eq(2)
    expect(core.default_capsule.queues).not_to include("projector", "archives")
    expect(core.default_capsule.mode).to eq(:random)
    expect(core.capsule("projector").concurrency).to eq(3)
    expect(core.capsule("projector").queues).to eq([ "projector" ])
    Logister::SidekiqWorkloadConfiguration.apply!(core)
    expect(core.total_concurrency).to eq(5)
  end

  it "preserves CLI total concurrency and supports an explicit projector split" do
    ENV["SIDEKIQ_CONCURRENCY"] = "8"
    ENV["SIDEKIQ_PROJECTOR_CONCURRENCY"] = "2"
    core = configured_core("-c", "5")

    expect(core.total_concurrency).to eq(5)
    expect(core.default_capsule.concurrency).to eq(3)
    expect(core.capsule("projector").concurrency).to eq(2)
  end

  it "refuses a split that removes general capacity or exceeds the budget" do
    ENV["SIDEKIQ_PROJECTOR_CONCURRENCY"] = "5"
    expect { configured_core("-c", "5") }.to raise_error(ArgumentError, /concurrency budget/)
    ENV.delete("SIDEKIQ_PROJECTOR_CONCURRENCY")
    expect { configured_core("-c", "1") }.to raise_error(ArgumentError, /concurrency budget/)
  end

  it "leaves archive isolation intact and makes the combined fallback fair" do
    archives = parsed_config("-C", Rails.root.join("config/sidekiq-archives.yml").to_s)
    combined = parsed_config("-C", Rails.root.join("config/sidekiq.yml").to_s)
    [ archives, combined ].each { |config| Logister::SidekiqWorkloadConfiguration.apply!(config) }

    expect(archives.capsules.keys).to eq([ "default" ])
    expect(archives.total_concurrency).to eq(1)
    expect(combined.capsules.keys).to eq([ "default" ])
    expect(combined.default_capsule.mode).to eq(:random)
  end

  def configured_core(*arguments)
    parsed_config("-C", Rails.root.join("config/sidekiq-core.yml").to_s, *arguments).tap do |config|
      Logister::SidekiqWorkloadConfiguration.apply!(config)
    end
  end

  def parsed_concurrency(*arguments)
    parsed_config(*arguments).concurrency
  end

  def parsed_config(*arguments)
    cli = Sidekiq::CLI.new
    cli.config = Sidekiq::Config.new
    cli.parse(arguments)
    cli.config
  end
end

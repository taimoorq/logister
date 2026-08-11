# frozen_string_literal: true

require "rails_helper"
require "sidekiq/cli"

RSpec.describe "Sidekiq configuration" do
  around do |example|
    previous_concurrency = ENV["SIDEKIQ_CONCURRENCY"]
    example.run
  ensure
    if previous_concurrency
      ENV["SIDEKIQ_CONCURRENCY"] = previous_concurrency
    else
      ENV.delete("SIDEKIQ_CONCURRENCY")
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

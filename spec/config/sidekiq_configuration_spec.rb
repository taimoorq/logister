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

  it "does not replace Sidekiq's parsed concurrency during Rails initialization" do
    initializer = Rails.root.join("config/initializers/sidekiq.rb").read

    expect(initializer).not_to match(/config\.concurrency\s*=/)
  end

  def parsed_concurrency(*arguments)
    cli = Sidekiq::CLI.new
    cli.config = Sidekiq::Config.new
    cli.parse(arguments)
    cli.config.concurrency
  end
end

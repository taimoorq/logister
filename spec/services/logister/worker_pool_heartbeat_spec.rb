# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::WorkerPoolHeartbeat do
  it "validates concurrency plus operational headroom" do
    pool = double("connection_pool", size: 6)

    status = described_class.status(concurrency: 5, connection_pool: pool)

    expect(status).to include(
      "size" => 6,
      "sidekiq_concurrency" => 5,
      "headroom" => 2,
      "required" => 7,
      "valid" => false
    )
  end
end

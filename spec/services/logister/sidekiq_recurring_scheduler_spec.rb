# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::SidekiqRecurringScheduler, type: :model do
  it "seeds every recurring Sidekiq job" do
    now = Time.zone.parse("2026-06-20T12:10:30Z")

    described_class::JOBS.each do |job_class|
      allow(job_class).to receive(:ensure_scheduled!)
    end

    described_class.install!(now)

    described_class::JOBS.each do |job_class|
      expect(job_class).to have_received(:ensure_scheduled!).with(now)
    end
  end

  it "reconciles missing schedules at most once per interval across worker processes" do
    now = Time.zone.parse("2026-06-20T12:10:30Z")
    redis = double("redis", set: true)
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(described_class).to receive(:install!)

    described_class.reconcile!(now)

    expect(redis).to have_received(:set).with(
      described_class::RECONCILE_KEY,
      now.utc.iso8601(6),
      nx: true,
      ex: 1.minute.to_i
    )
    expect(described_class).to have_received(:install!).with(now)
  end
end

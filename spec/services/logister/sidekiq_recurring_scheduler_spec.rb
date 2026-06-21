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
end

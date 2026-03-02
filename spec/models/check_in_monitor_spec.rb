# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckInMonitor, type: :model do
  describe "#status" do
    it "returns missed when latest check-in exceeds interval + grace" do
      monitor = described_class.new(
        project: projects(:one),
        slug: "nightly-job",
        environment: "production",
        expected_interval_seconds: 60,
        last_check_in_at: 2.minutes.ago,
        last_status: "ok"
      )

      expect(monitor.status).to eq("missed")
    end

    it "returns error when last status is error" do
      monitor = described_class.new(
        project: projects(:one),
        slug: "nightly-job",
        environment: "production",
        expected_interval_seconds: 60,
        last_check_in_at: Time.current,
        last_status: "error"
      )

      expect(monitor.status).to eq("error")
    end
  end
end

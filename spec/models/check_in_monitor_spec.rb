# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckInMonitor, type: :model do
  describe "factory" do
    it "builds a valid check-in monitor" do
      monitor = build(:check_in_monitor, project: projects(:one))

      expect(monitor).to be_valid
      expect(monitor.project).to eq(projects(:one))
    end

    it "creates a monitor with a matching last event" do
      monitor = create(:check_in_monitor, :with_last_event, project: projects(:one), api_key: api_keys(:one))

      expect(monitor).to be_persisted
      expect(monitor.last_event).to be_check_in
      expect(monitor.last_event.project).to eq(projects(:one))
    end
  end

  describe "#status" do
    it "returns missed when latest check-in exceeds interval + grace" do
      monitor = build(:check_in_monitor,
        project: projects(:one),
        slug: "nightly-job",
        expected_interval_seconds: 60,
        last_check_in_at: 2.minutes.ago,
        last_status: "ok")

      expect(monitor.status).to eq("missed")
    end

    it "returns error when last status is error" do
      monitor = build(:check_in_monitor,
        project: projects(:one),
        slug: "nightly-job",
        expected_interval_seconds: 60,
        last_check_in_at: Time.current,
        last_status: "error")

      expect(monitor.status).to eq("error")
    end
  end
end

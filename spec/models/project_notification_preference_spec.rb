# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectNotificationPreference, type: :model do
  describe ".for" do
    it "creates default project email preferences" do
      preference = described_class.for(user: users(:one), project: projects(:one))

      expect(preference).to be_persisted
      expect(preference.first_occurrence_enabled).to be true
      expect(preference.digest_frequency).to eq("none")
      expect(preference.digest_send_hour).to eq(9)
      expect(preference.time_zone).to eq("UTC")
    end
  end

  describe "#due_digest_window" do
    it "returns the previous day after the local send hour for daily digests" do
      preference = build(:project_notification_preference, :daily, digest_send_hour: 9, time_zone: "UTC")

      window = preference.due_digest_window(Time.zone.parse("2026-05-09 09:15:00 UTC"))

      expect(window.map(&:utc)).to eq([
        Time.zone.parse("2026-05-08 00:00:00 UTC"),
        Time.zone.parse("2026-05-09 00:00:00 UTC")
      ])
    end

    it "waits until Monday send hour for weekly digests" do
      preference = build(:project_notification_preference, :weekly, digest_send_hour: 9, time_zone: "UTC")

      expect(preference.due_digest_window(Time.zone.parse("2026-05-10 10:00:00 UTC"))).to be_nil
      expect(preference.due_digest_window(Time.zone.parse("2026-05-11 08:59:00 UTC"))).to be_nil

      window = preference.due_digest_window(Time.zone.parse("2026-05-11 09:00:00 UTC"))
      expect(window.map(&:utc)).to eq([
        Time.zone.parse("2026-05-04 00:00:00 UTC"),
        Time.zone.parse("2026-05-11 00:00:00 UTC")
      ])
    end
  end

  it "rejects unknown time zones" do
    preference = build(:project_notification_preference, time_zone: "Mars/Base")

    expect(preference).not_to be_valid
    expect(preference.errors[:time_zone]).to include("is not supported")
  end
end

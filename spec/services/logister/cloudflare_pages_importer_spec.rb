# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::CloudflarePagesImporter do
  describe ".call" do
    it "skips missing settings" do
      result = described_class.call(nil)

      expect(result).to be_skipped
      expect(result.reason).to eq(:missing_setting)
    end

    it "skips settings for other providers" do
      setting = build(:project_integration_setting, project: create(:project, :android), provider: "google_play")

      result = described_class.call(setting)

      expect(result).to be_skipped
      expect(result.reason).to eq(:wrong_provider)
    end

    it "skips unconfigured Cloudflare settings" do
      setting = build(:project_integration_setting, enabled: false)

      result = described_class.call(setting)

      expect(result).to be_skipped
      expect(result.reason).to eq(:not_configured)
    end

    it "returns the fetcher placeholder for configured Cloudflare settings" do
      setting = build(:project_integration_setting, enabled: true)

      result = described_class.call(setting)

      expect(result).to be_skipped
      expect(result.reason).to eq(:fetcher_not_implemented)
      expect(result.setting).to eq(setting)
    end
  end
end

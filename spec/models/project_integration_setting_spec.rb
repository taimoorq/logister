# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectIntegrationSetting, type: :model do
  describe ".for" do
    it "finds or initializes a provider setting for a project" do
      project = create(:project, :cloudflare_pages)

      setting = described_class.for(project: project, provider: "cloudflare_pages")

      expect(setting).to be_new_record
      expect(setting.project).to eq(project)
      expect(setting.provider).to eq("cloudflare_pages")
    end
  end

  describe "validations" do
    it "requires Cloudflare identifiers" do
      setting = build(:project_integration_setting, account_id: "", external_project_name: "")

      expect(setting).not_to be_valid
      expect(setting.errors[:account_id]).to be_present
      expect(setting.errors[:external_project_name]).to be_present
    end

    it "requires provider to match project integration type" do
      setting = build(:project_integration_setting, project: create(:project, :ruby))

      expect(setting).not_to be_valid
      expect(setting.errors[:provider]).to include("does not match this project's integration type")
    end

    it "allows mobile aggregate providers for matching mobile project types" do
      android_project = create(:project, :android)
      ios_project = create(:project, :ios)

      google_play = build(:project_integration_setting, project: android_project, provider: "google_play")
      app_store = build(:project_integration_setting, project: ios_project, provider: "app_store_connect")

      expect(google_play).to be_valid
      expect(app_store).to be_valid
    end
  end

  describe "#configured?" do
    it "is true for enabled Cloudflare settings with identifiers and credential reference" do
      setting = build(:project_integration_setting, enabled: true)

      expect(setting).to be_configured
    end

    it "is false when the credential reference is missing" do
      setting = build(:project_integration_setting, enabled: true, credential_reference: nil)

      expect(setting).not_to be_configured
    end
  end
end

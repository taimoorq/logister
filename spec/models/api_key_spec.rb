# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiKey, type: :model do
  describe "associations" do
    it "belongs to user" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq(:belongs_to)
    end

    it "belongs to project" do
      association = described_class.reflect_on_association(:project)
      expect(association.macro).to eq(:belongs_to)
    end

    it "has many ingest_events dependent destroy" do
      association = described_class.reflect_on_association(:ingest_events)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end
  end

  describe "scopes" do
    it "active excludes revoked" do
      key = api_keys(:one)
      expect(described_class.active).to include(key)
      key.revoke!
      expect(described_class.active).not_to include(key)
    end
  end

  describe "validations" do
    it "validates presence of name and token_digest" do
      key = described_class.new(project: projects(:one), user: users(:one))
      expect(key).not_to be_valid
      expect(key.errors[:name]).to be_present
    end
  end

  describe ".authenticate" do
    it "returns api_key for valid token" do
      key = ApiKey.authenticate("test-token-one")
      expect(key).to eq(api_keys(:one))
    end

    it "returns nil for invalid token" do
      expect(ApiKey.authenticate("wrong-token")).to be_nil
    end

    it "returns nil for blank token" do
      expect(ApiKey.authenticate("")).to be_nil
      expect(ApiKey.authenticate(nil)).to be_nil
    end

    it "returns nil for revoked key" do
      api_keys(:one).revoke!
      expect(ApiKey.authenticate("test-token-one")).to be_nil
    end
  end

  describe "#revoke!" do
    it "sets revoked_at" do
      key = api_keys(:one)
      key.revoke!
      expect(key.reload.revoked_at).to be_present
      expect(key).not_to be_active
    end
  end

  describe "#active?" do
    it "is true when revoked_at is nil" do
      expect(api_keys(:one)).to be_active
    end

    it "is false when revoked" do
      api_keys(:one).revoke!
      expect(api_keys(:one).reload).not_to be_active
    end
  end

  describe "#touch_last_used!" do
    it "updates last_used_at" do
      key = api_keys(:one)
      travel_to Time.current do
        key.touch_last_used!
        expect(key.reload.last_used_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe "token generation on create" do
    it "sets token_digest and exposes plain_token" do
      key = described_class.create!(user: users(:one), project: projects(:one), name: "New key")
      expect(key.token_digest).to be_present
      expect(key.plain_token).to be_present
      expect(key.plain_token).to start_with("logister_")
      expect(ApiKey.authenticate(key.plain_token)).to eq(key)
    end

    it "supports a configurable token prefix" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("LOGISTER_API_KEY_PREFIX", "logister").and_return("prod")

      key = described_class.create!(user: users(:one), project: projects(:one), name: "Prefixed key")

      expect(key.plain_token).to start_with("prod_")
      expect(ApiKey.authenticate(key.plain_token)).to eq(key)
    end
  end
end

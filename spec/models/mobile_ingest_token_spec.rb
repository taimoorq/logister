# frozen_string_literal: true

require "rails_helper"

RSpec.describe MobileIngestToken, type: :model do
  describe "associations" do
    it "belongs to project and api_key" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
      expect(described_class.reflect_on_association(:api_key).macro).to eq(:belongs_to)
    end
  end

  describe "validations" do
    it "requires a mobile project matching the token platform" do
      project = create(:project, :ios)
      api_key = create(:api_key, project: project, user: project.user)

      token = described_class.new(
        project: project,
        api_key: api_key,
        platform: "android",
        service: "com.example.app",
        environment: "production",
        expires_at: 15.minutes.from_now
      )

      expect(token).not_to be_valid
      expect(token.errors[:platform]).to include("must match the project integration kind")
    end

    it "requires the parent api key to belong to the same project" do
      project = create(:project, :android)
      other_api_key = create(:api_key)

      token = build(:mobile_ingest_token, project: project, api_key: other_api_key)

      expect(token).not_to be_valid
      expect(token.errors[:api_key]).to include("must belong to the same project")
    end

    it "rejects revoked parent api keys" do
      project = create(:project, :android)
      api_key = create(:api_key, :revoked, project: project, user: project.user)

      token = build(:mobile_ingest_token, project: project, api_key: api_key)

      expect(token).not_to be_valid
      expect(token.errors[:api_key]).to include("is revoked")
    end

    it "rejects archived projects" do
      project = create(:project, :android, :archived)
      api_key = build(:api_key, project: project, user: project.user)
      token = described_class.new(
        project: project,
        api_key: api_key,
        platform: "android",
        service: "com.example.app",
        environment: "production",
        expires_at: 15.minutes.from_now
      )

      expect(token).not_to be_valid
      expect(token.errors[:project]).to include("is archived")
    end

    it "rejects unsupported event types" do
      token = build(:mobile_ingest_token, allowed_event_types: [ "error", "deployment" ])

      expect(token).not_to be_valid
      expect(token.errors[:allowed_event_types].join).to include("deployment")
    end

    it "rejects overly long expiry windows" do
      token = build(:mobile_ingest_token, expires_at: 2.hours.from_now)

      expect(token).not_to be_valid
      expect(token.errors[:expires_at]).to include("must be within #{described_class::MAX_EXPIRES_IN_SECONDS} seconds")
    end
  end

  describe "token generation" do
    it "stores a digest and exposes the plaintext token once" do
      token = create(:mobile_ingest_token)

      expect(token.plain_token).to start_with("logister_mobile_")
      expect(token.token_digest).to eq(described_class.digest(token.plain_token))
      expect(described_class.authenticate(token.plain_token)).to eq(token)
    end
  end

  describe ".authenticate" do
    it "returns nil for expired tokens" do
      token = create(:mobile_ingest_token)
      token.update_column(:expires_at, 1.minute.ago)

      expect(described_class.authenticate(token.plain_token)).to be_nil
    end

    it "returns nil for revoked tokens" do
      token = create(:mobile_ingest_token)
      token.revoke!

      expect(described_class.authenticate(token.plain_token)).to be_nil
    end

    it "returns nil when the parent api key is revoked" do
      token = create(:mobile_ingest_token)
      token.api_key.revoke!

      expect(described_class.authenticate(token.plain_token)).to be_nil
    end

    it "returns nil when the project is archived" do
      token = create(:mobile_ingest_token)
      token.project.archive!

      expect(described_class.authenticate(token.plain_token)).to be_nil
    end
  end

  describe "#context_bindings" do
    it "includes only present immutable bindings" do
      token = build(:mobile_ingest_token, release: nil, session_id: nil)

      expect(token.context_bindings).to eq(
        "platform" => "android",
        "service" => "com.example.app",
        "environment" => "production"
      )
    end
  end
end

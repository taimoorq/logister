# frozen_string_literal: true

require "rails_helper"

RSpec.describe CliDeviceAuthorization, type: :model do
  describe ".issue!" do
    it "returns one-time device and user codes without storing the raw device code" do
      authorization = described_class.issue!(client_name: "Logister CLI")

      expect(authorization.plain_device_code).to be_present
      expect(authorization.device_code_digest).to eq(described_class.digest(authorization.plain_device_code))
      expect(authorization.device_code_digest).not_to include(authorization.plain_device_code)
      expect(authorization.user_code_display).to match(/\A[A-Z0-9]{4}-[A-Z0-9]{4}\z/)
      expect(authorization).to be_pending
    end
  end

  describe "#exchange!" do
    it "creates exactly one read-scoped CLI token after browser approval" do
      user = create(:user)
      project = create(:project, user: user)
      authorization = described_class.issue!(client_name: "Logister CLI")
      authorization.approve!(user: user, all_projects: false, allowed_project_ids: [ project.id ])

      result = authorization.exchange!

      expect(result.status).to eq(:authorized)
      expect(result.access_token.plain_token).to start_with("logister_cli_")
      expect(result.access_token.scopes).to eq(CliAccessToken::READ_SCOPES)
      expect(result.access_token.allowed_project_ids).to eq([ project.id ])
      expect(authorization.reload).to be_consumed
      expect(authorization.exchange!.status).to eq(:invalid_grant)
    end

    it "reports pending, slow polling, denied, and expired states without issuing a token" do
      pending = create(:cli_device_authorization)

      expect(pending.exchange!.status).to eq(:authorization_pending)
      expect(pending.exchange!.status).to eq(:slow_down)
      expect(create(:cli_device_authorization, :denied).exchange!.status).to eq(:access_denied)
      expect(create(:cli_device_authorization, :expired).exchange!.status).to eq(:expired_token)
    end
  end
end

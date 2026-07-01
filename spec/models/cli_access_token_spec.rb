# frozen_string_literal: true

require "rails_helper"

RSpec.describe CliAccessToken, type: :model do
  it "generates a plaintext token once and stores only the digest" do
    token = create(:cli_access_token)

    expect(token.plain_token).to start_with("logister_cli_")
    expect(token.token_digest).to eq(described_class.digest(token.plain_token))
    expect(described_class.authenticate(token.plain_token)).to eq(token)
  end

  it "does not authenticate expired or revoked tokens" do
    expired = create(:cli_access_token, expires_at: 1.minute.from_now)
    revoked = create(:cli_access_token)
    raw_expired = expired.plain_token
    raw_revoked = revoked.plain_token

    expired.update!(expires_at: 1.minute.ago)
    revoked.revoke!

    expect(described_class.authenticate(raw_expired)).to be_nil
    expect(described_class.authenticate(raw_revoked)).to be_nil
  end

  it "limits accessible projects when all_projects is false" do
    user = create(:user)
    allowed = create(:project, user: user)
    other = create(:project, user: user)
    token = create(:cli_access_token, user: user, all_projects: false, allowed_project_ids: [ allowed.id ])

    expect(token.accessible_projects).to contain_exactly(allowed)
    expect(token.accessible_projects).not_to include(other)
  end

  it "rejects unsupported scopes and inaccessible projects" do
    user = create(:user)
    other_project = create(:project)
    token = build(
      :cli_access_token,
      user: user,
      all_projects: false,
      allowed_project_ids: [ other_project.id ],
      scopes: [ "projects:read", "admin:everything" ]
    )

    expect(token).not_to be_valid
    expect(token.errors[:scopes]).to include("contains unsupported values: admin:everything")
    expect(token.errors[:allowed_project_ids].join).to include(other_project.id.to_s)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorGroupExternalLink, type: :model do
  it "normalizes GitHub issue metadata from the URL" do
    link = build(:error_group_external_link, url: "https://github.com/acme/api/issues/99?foo=bar")

    expect(link).to be_valid
    expect(link.url).to eq("https://github.com/acme/api/issues/99")
    expect(link.link_type).to eq("issue")
    expect(link.repository_full_name).to eq("acme/api")
    expect(link.external_id).to eq("99")
    expect(link.display_label).to eq("acme/api issue #99")
  end

  it "normalizes GitHub pull request metadata from the URL" do
    link = build(:error_group_external_link, url: "https://github.com/acme/api/pull/15")

    expect(link).to be_valid
    expect(link.link_type).to eq("pull_request")
    expect(link.display_label).to eq("acme/api PR #15")
  end

  it "rejects non-issue GitHub URLs" do
    link = build(:error_group_external_link, url: "https://github.com/acme/api/actions/runs/15")

    expect(link).not_to be_valid
    expect(link.errors[:url]).to include("must be a GitHub issue or pull request URL")
  end

  it "requires the error group to belong to the same project" do
    project = create(:project)
    other_group = create(:error_group)
    link = build(:error_group_external_link, project: project, error_group: other_group)

    expect(link).not_to be_valid
    expect(link.errors[:error_group]).to include("must belong to the project")
  end
end

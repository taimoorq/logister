# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::IssueDeepLink do
  it "builds a prefilled GitHub new issue URL for the first project source repository" do
    project = create(:project, name: "Checkout API")
    group = create(:error_group, project: project, title: "RuntimeError in Checkout", fingerprint: "checkout-runtime", occurrence_count: 3)
    event = create(:ingest_event, project: project, context: { "release" => "abc123" })
    create(:project_source_repository, project: project, full_name: "acme/checkout", runtime_root: "/app")

    url = described_class.call(
      project: project,
      group: group,
      event: event,
      source_excerpt: { source_url: "https://github.com/acme/checkout/blob/main/app/checkout.rb#L12" },
      logister_url: "https://logister.example/projects/#{project.uuid}/inbox?group_uuid=#{group.uuid}"
    )

    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query).to_h

    expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq("https://github.com/acme/checkout/issues/new")
    expect(params["title"]).to eq("[Checkout API] RuntimeError in Checkout")
    expect(params["body"]).to include("Occurrences: 3")
    expect(params["body"]).to include("Fingerprint: `checkout-runtime`")
    expect(params["body"]).to include("Release: `abc123`")
    expect(params["body"]).to include("https://github.com/acme/checkout/blob/main/app/checkout.rb#L12")
  end

  it "returns nil when the project has no source repository" do
    project = create(:project)
    group = create(:error_group, project: project)

    expect(
      described_class.call(project: project, group: group, event: nil, source_excerpt: nil, logister_url: nil)
    ).to be_nil
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::IssuePayload do
  it "includes release, deployment, source, and Logister links" do
    project = create(:project, name: "Checkout API")
    group = create(
      :error_group,
      project: project,
      title: "RuntimeError in Checkout",
      fingerprint: "checkout-runtime",
      occurrence_count: 3,
      last_seen_release: "2026.06.18"
    )
    deployment = build(
      :project_deployment,
      project: project,
      repository_full_name: "acme/checkout",
      release: "2026.06.18",
      commit_sha: "def5678"
    )
    deployment_context = ProjectDeploymentContext::Result.new(
      deployment: deployment,
      previous_deployment: nil,
      started_after: true,
      minutes_after: 12,
      exact_release: true
    )

    payload = described_class.call(
      project: project,
      group: group,
      event: nil,
      source_excerpt: { source_url: "https://github.com/acme/checkout/blob/main/app/checkout.rb#L12" },
      deployment_context: deployment_context,
      logister_url: "https://logister.example/projects/#{project.uuid}/inbox?group_uuid=#{group.uuid}"
    )

    expect(payload.title).to eq("[Checkout API] RuntimeError in Checkout")
    expect(payload.body).to include("Occurrences: 3")
    expect(payload.body).to include("Fingerprint: `checkout-runtime`")
    expect(payload.body).to include("Release: `2026.06.18`")
    expect(payload.body).to include("Deployment: `2026.06.18`")
    expect(payload.body).to include("acme/checkout")
    expect(payload.body).to include("def5678")
    expect(payload.body).to include("https://github.com/acme/checkout/blob/main/app/checkout.rb#L12")
    expect(payload.body).to include("https://logister.example/projects/#{project.uuid}/inbox?group_uuid=#{group.uuid}")
  end

  it "renders attacker-controlled titles and names as inert code spans" do
    project = create(:project, name: "Shop [docs](https://evil.example) @org/team")
    group = create(
      :error_group,
      project: project,
      title: "Boom ``` </details>\n## Pwned\n![x](https://evil.example/x.png) @octocat #1",
      fingerprint: "boom"
    )

    payload = described_class.call(project: project, group: group)
    lines = payload.body.lines(chomp: true)

    expect(lines).to include("- Project: `Shop [docs](https://evil.example) @org/team`")
    expect(lines).to include("- Error: ````Boom ``` </details> ## Pwned ![x](https://evil.example/x.png) @octocat #1````")
    expect(lines.grep(/\A## /)).to eq([ "## Logister error", "## Notes" ])
  end

  it "pads code spans whose content starts or ends with a backtick" do
    project = create(:project, name: "`edge`")
    group = create(:error_group, project: project, fingerprint: "edge")
    group.title = " \n "

    body = described_class.call(project: project, group: group).body

    expect(body).to include("- Project: `` `edge` ``")
    expect(body).to include("- Error: ` `")
  end

  it "omits source URLs that are not https links on the GitHub web host" do
    project = create(:project)
    group = create(:error_group, project: project, fingerprint: "source")

    [
      "https://evil.example/acme/checkout/blob/main/app.rb#L1",
      "javascript:alert(1)",
      "http://github.com/acme/checkout/blob/main/app.rb#L1",
      "https://github.com/acme/checkout) [click here](https://evil.example"
    ].each do |source_url|
      body = described_class.call(project: project, group: group, source_excerpt: { "source_url" => source_url }).body

      expect(body).not_to include("Source:"), "expected #{source_url.inspect} to be omitted"
    end
  end
end

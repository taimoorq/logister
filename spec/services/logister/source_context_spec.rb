# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Logister::SourceContext do
  let(:env) { {} }

  it "prefers explicit source environment variables" do
    context = described_class.current(
      root: Rails.root,
      env: env.merge(
        "LOGISTER_ENVIRONMENT" => "production",
        "LOGISTER_SERVICE" => "logister-web",
        "LOGISTER_RELEASE" => "v2.6.1",
        "LOGISTER_REPOSITORY" => "acme/logister",
        "LOGISTER_COMMIT_SHA" => "abc1234",
        "LOGISTER_BRANCH" => "main",
        "LOGISTER_WORKFLOW_RUN_URL" => "https://github.com/acme/logister/actions/runs/1"
      )
    )

    expect(context.event_context).to include(
      environment: "production",
      service: "logister-web",
      release: "v2.6.1",
      repository: "acme/logister",
      commit_sha: "abc1234",
      branch: "main"
    )
    expect(context.deployment_payload).to include(
      workflow_run_url: "https://github.com/acme/logister/actions/runs/1"
    )
  end

  it "falls back to local git metadata without shelling out" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      git_dir = root.join(".git")
      git_dir.join("refs/heads/feature").mkpath
      git_dir.join("HEAD").write("ref: refs/heads/feature/source-context\n")
      git_dir.join("refs/heads/feature/source-context").write("def5678abc9012\n")
      git_dir.join("config").write(<<~CONFIG)
        [remote "origin"]
          url = git@github.com:taimoorq/logister.git
      CONFIG

      context = described_class.current(root: root, env: env)

      expect(context.repository).to eq("taimoorq/logister")
      expect(context.commit_sha).to eq("def5678abc9012")
      expect(context.branch).to eq("feature/source-context")
      expect(context.release).to eq("logister@def5678")
    end
  end

  it "adds missing source context without overwriting existing payload fields" do
    source_context = described_class.current(
      root: Rails.root,
      env: env.merge(
        "LOGISTER_REPOSITORY" => "acme/logister",
        "LOGISTER_COMMIT_SHA" => "abc1234",
        "LOGISTER_BRANCH" => "main",
        "LOGISTER_RELEASE" => "v2.6.1"
      )
    )
    payload = {
      context: {
        repository: "custom/repo",
        deployment: {
          release: "custom-release"
        }
      }
    }

    enriched = described_class.enrich_payload(payload, source_context: source_context)

    expect(enriched[:context]).to include(
      repository: "custom/repo",
      commit_sha: "abc1234",
      branch: "main"
    )
    expect(enriched[:context][:deployment]).to include(
      release: "custom-release",
      repository: "acme/logister",
      commit_sha: "abc1234"
    )
  end
end

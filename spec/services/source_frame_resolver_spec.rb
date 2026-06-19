# frozen_string_literal: true

require "rails_helper"

RSpec.describe SourceFrameResolver do
  FetchResult = Data.define(:content, :sha, :html_url)

  class FakeGithubFetcher
    attr_reader :requests

    def initialize(result)
      @result = result
      @requests = []
    end

    def fetch(**kwargs)
      @requests << kwargs
      @result
    end
  end

  class RefAwareGithubFetcher
    attr_reader :requests

    def initialize(results_by_ref)
      @results_by_ref = results_by_ref
      @requests = []
    end

    def fetch(**kwargs)
      @requests << kwargs
      @results_by_ref[kwargs[:ref]]
    end
  end

  it "returns a GitHub source excerpt for the mapped frame" do
    project = create(:project)
    installation = create(:github_installation)
    create(
      :project_source_repository,
      project: project,
      github_installation: installation,
      external_id: 123,
      full_name: "acme/storefront",
      runtime_root: "/srv/app",
      source_root: "apps/web",
      default_branch: "main"
    )
    event = create(:ingest_event, project: project, context: {
      "commit_sha" => "abc1234",
      "repository" => "acme/storefront"
    })
    fetcher = FakeGithubFetcher.new(
      FetchResult.new(
        content: "one\ntwo\nthree\nfour\nfive\nsix\n",
        sha: "file-sha",
        html_url: "https://github.com/acme/storefront/blob/abc1234/apps/web/app/models/order.rb"
      )
    )

    result = described_class.call(
      project: project,
      event: event,
      frame: { file: "/srv/app/app/models/order.rb", line_number: 3 },
      radius: 1,
      fetcher: fetcher
    )

    expect(result[:path]).to eq("acme/storefront:apps/web/app/models/order.rb")
    expect(result[:source_url]).to end_with("#L3")
    expect(result[:lines].map { |line| line[:code] }).to eq(%w[two three four])
    expect(fetcher.requests.first).to include(
      owner: "acme",
      repo: "storefront",
      path: "apps/web/app/models/order.rb",
      ref: "abc1234",
      installation: installation,
      repository_id: 123
    )
  end

  it "returns nil when no source repositories are configured" do
    project = create(:project)
    event = create(:ingest_event, project: project)

    result = described_class.call(
      project: project,
      event: event,
      frame: { file: "app/models/order.rb", line_number: 3 },
      fetcher: FakeGithubFetcher.new(nil)
    )

    expect(result).to be_nil
  end

  it "uses the synced GitHub repository installation when present" do
    project = create(:project)
    github_repository = create(:github_repository, external_id: 987, full_name: "acme/api")
    create(
      :project_source_repository,
      project: project,
      github_repository: github_repository,
      github_installation: nil,
      external_id: nil,
      full_name: "acme/api"
    )
    event = create(:ingest_event, project: project)
    fetcher = FakeGithubFetcher.new(
      FetchResult.new(
        content: "one\ntwo\nthree\n",
        sha: "file-sha",
        html_url: "https://github.com/acme/api/blob/main/app/models/order.rb"
      )
    )

    described_class.call(
      project: project,
      event: event,
      frame: { file: "/app/app/models/order.rb", line_number: 2 },
      radius: 1,
      fetcher: fetcher
    )

    expect(fetcher.requests.first).to include(
      installation: github_repository.github_installation,
      repository_id: 987
    )
  end

  it "adds CODEOWNERS metadata to GitHub excerpts" do
    project = create(:project)
    installation = create(:github_installation)
    repository = create(
      :project_source_repository,
      project: project,
      github_installation: installation,
      external_id: 123,
      full_name: "acme/storefront"
    )
    event = create(:ingest_event, project: project)
    fetcher = FakeGithubFetcher.new(
      FetchResult.new(
        content: "one\ntwo\nthree\n",
        sha: "file-sha",
        html_url: "https://github.com/acme/storefront/blob/main/app/models/order.rb"
      )
    )
    codeowners = Github::CodeownersResolver::Result.new(
      owners: [ "api-owner@example.com" ],
      matched_users: [],
      codeowners_path: "CODEOWNERS",
      line_number: 2
    )
    codeowners_resolver = instance_double(Github::CodeownersResolver, call: codeowners)

    result = described_class.call(
      project: project,
      event: event,
      frame: { file: "/app/app/models/order.rb", line_number: 2 },
      fetcher: fetcher,
      codeowners_resolver: codeowners_resolver
    )

    expect(result[:codeowners]).to eq(codeowners)
    expect(codeowners_resolver).to have_received(:call).with(
      project: project,
      repository: repository,
      source_path: "app/models/order.rb",
      ref: "main"
    )
  end

  it "uses an indexed deployment commit before the raw release ref" do
    project = create(:project)
    installation = create(:github_installation)
    repository = create(
      :project_source_repository,
      project: project,
      github_installation: installation,
      external_id: 123,
      full_name: "acme/storefront",
      default_branch: "main"
    )
    create(
      :project_deployment,
      project: project,
      project_source_repository: repository,
      repository_full_name: "acme/storefront",
      release: "2026.06.18",
      environment: "production",
      commit_sha: "def5678"
    )
    event = create(:ingest_event, project: project, context: {
      "release" => "2026.06.18",
      "environment" => "production",
      "repository" => "acme/storefront"
    })
    fetcher = RefAwareGithubFetcher.new(
      "def5678" => FetchResult.new(
        content: "one\ntwo\nthree\n",
        sha: "file-sha",
        html_url: "https://github.com/acme/storefront/blob/def5678/app/models/order.rb"
      )
    )

    result = described_class.call(
      project: project,
      event: event,
      frame: { file: "/app/app/models/order.rb", line_number: 2 },
      radius: 1,
      fetcher: fetcher
    )

    expect(result[:ref]).to eq("def5678")
    expect(fetcher.requests.first).to include(path: "app/models/order.rb", ref: "def5678")
    expect(fetcher.requests.map { |request| request[:ref] }).not_to include("2026.06.18")
  end

  it "returns diagnostics when no source repositories are enabled" do
    project = create(:project)
    event = create(:ingest_event, project: project)

    result = described_class.resolve(
      project: project,
      event: event,
      frame: { file: "/app/app/models/order.rb", line_number: 2 },
      fetcher: FakeGithubFetcher.new(nil)
    )

    expect(result.excerpt).to be_nil
    expect(result.diagnostics).to include(
      status: :no_repositories,
      message: "No GitHub source repository mapping is enabled for this project."
    )
  end

  it "does not resolve synced repositories until one is explicitly connected" do
    project = create(:project)
    installation = create(:github_installation)
    github_repository = create(:github_repository, github_installation: installation, full_name: "acme/storefront")
    create(:project_github_installation, project: project, github_installation: installation)
    event = create(:ingest_event, project: project, context: {
      "repository" => "acme/storefront",
      "commit_sha" => "abc1234"
    })
    frame = { file: "/srv/app/app/models/order.rb", line_number: 2 }

    unresolved = described_class.resolve(
      project: project,
      event: event,
      frame: frame,
      fetcher: FakeGithubFetcher.new(nil)
    )

    connector_result = ProjectSourceRepositoryConnector.new(
      project: project,
      attributes: {
        provider: "github",
        github_repository_id: github_repository.id,
        runtime_root: "/srv/app",
        enabled: true
      }
    ).build
    connector_result.source_repository.save!
    fetcher = FakeGithubFetcher.new(
      FetchResult.new(
        content: "one\ntwo\nthree\n",
        sha: "file-sha",
        html_url: "https://github.com/acme/storefront/blob/abc1234/app/models/order.rb"
      )
    )

    resolved = described_class.resolve(
      project: project,
      event: event,
      frame: frame,
      fetcher: fetcher
    )

    expect(unresolved.diagnostics[:status]).to eq(:no_repositories)
    expect(resolved.diagnostics[:status]).to eq(:resolved)
    expect(resolved.excerpt[:repository]).to eq("acme/storefront")
    expect(fetcher.requests.first).to include(path: "app/models/order.rb", ref: "abc1234")
  end
end

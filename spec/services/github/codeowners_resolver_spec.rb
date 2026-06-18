# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::CodeownersResolver do
  CodeownersFetchResult = Data.define(:content, :sha, :html_url)

  class FakeCodeownersFetcher
    attr_reader :requests

    def initialize(files)
      @files = files
      @requests = []
    end

    def fetch(owner:, repo:, path:, ref:, installation:, repository_id: nil)
      @requests << {
        owner: owner,
        repo: repo,
        path: path,
        ref: ref,
        installation: installation,
        repository_id: repository_id
      }
      content = @files[path]
      content ? CodeownersFetchResult.new(content: content, sha: "sha", html_url: "https://github.example/#{path}") : nil
    end
  end

  it "fetches the first CODEOWNERS file and matches owners to project users by email" do
    project = create(:project)
    member = create(:user, email: "api-owner@example.com")
    create(:project_membership, project: project, user: member)
    repository = create(
      :project_source_repository,
      project: project,
      full_name: "acme/api",
      github_repository: create(:github_repository, full_name: "acme/api", external_id: 987)
    )
    fetcher = FakeCodeownersFetcher.new(
      ".github/CODEOWNERS" => <<~CODEOWNERS
        * @global-owner
        app/models/ api-owner@example.com @acme/backend
      CODEOWNERS
    )

    result = described_class.new(fetcher: fetcher).call(
      project: project,
      repository: repository,
      source_path: "app/models/order.rb",
      ref: "main"
    )

    expect(result.owners).to eq([ "api-owner@example.com", "@acme/backend" ])
    expect(result.matched_users).to contain_exactly(member)
    expect(result.codeowners_path).to eq(".github/CODEOWNERS")
    expect(fetcher.requests.first).to include(
      owner: "acme",
      repo: "api",
      path: ".github/CODEOWNERS",
      ref: "main",
      installation: repository.effective_github_installation,
      repository_id: 987
    )
  end

  it "falls back through GitHub's CODEOWNERS search locations" do
    project = create(:project)
    repository = create(:project_source_repository, project: project, full_name: "acme/api")
    fetcher = FakeCodeownersFetcher.new(
      "CODEOWNERS" => "*.rb @ruby-owner"
    )

    result = described_class.new(fetcher: fetcher).call(
      project: project,
      repository: repository,
      source_path: "app/models/order.rb",
      ref: "main"
    )

    expect(result.owners).to eq([ "@ruby-owner" ])
    expect(result.codeowners_path).to eq("CODEOWNERS")
    expect(fetcher.requests.map { |request| request[:path] }).to eq([ ".github/CODEOWNERS", "CODEOWNERS" ])
  end
end

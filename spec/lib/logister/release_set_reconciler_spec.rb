# frozen_string_literal: true

require "rails_helper"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe Logister::ReleaseSetReconciler do
  FakeHttp = Struct.new(:responses) do
    def get(url)
      responses.fetch(url, [ 404, "" ])
    end
  end

  let(:repo_root) { @repo_root }
  let(:release_set_path) { repo_root.join("config/release-sets/v3.6.yml") }
  let(:identity) { @released_identity }
  let(:release_sha) { @release_sha }

  around do |example|
    Dir.mktmpdir("logister-reconciler") do |directory|
      @repo_root = Pathname(directory)
      prepare_released_source
      example.run
    end
  end
  let(:tarball) { "canonical CLI npm tarball bytes" }
  let(:tarball_url) { "https://registry.npmjs.org/logister-cli/-/logister-cli-1.0.0.tgz" }
  let(:responses) { public_responses }

  it "reconciles the backend and every package channel into a public receipt" do
    reconciler = described_class.new(repo_root: repo_root, release_set_path: release_set_path, http: FakeHttp.new(responses))
    receipt = reconciler.reconcile

    expect(receipt).to include(status: "complete", release_set: "backend-v3-6")
    expect(receipt.fetch(:errors)).to be_empty
    expect(receipt.fetch(:checks).pluck(:status)).to all(eq("verified"))
    expect(receipt.dig(:components, "logister-cli", :channels)).to include("homebrew-logister", "scoop-logister")
    expect(reconciler.catalog(receipt)).to include(
      backend: { version: "3.6" },
      addons: include(
        "logister-android" => { version: "0.4.0" },
        "logister-js" => { version: "0.4.1" }
      )
    )
  end

  it "stays pending and names a missing public channel" do
    responses[maven_url] = [ 404, "" ]
    receipt = described_class.new(repo_root: repo_root, release_set_path: release_set_path, http: FakeHttp.new(responses)).reconcile

    expect(receipt.fetch(:status)).to eq("pending")
    expect(receipt.fetch(:errors)).to include(match(%r{logister-android/maven_central: public endpoint returned HTTP 404}))
    expect(receipt.fetch(:checks)).to include(
      component: "logister-android",
      channel: "maven_central",
      url: maven_url,
      status: "pending"
    )
  end

  it "uses the release tag's contract after catalog documentation changes on main" do
    guide = repo_root.join("docs/mobile-add-ons.md")
    guide.write("#{guide.read}\nUpdated verified catalog references.\n")
    git!("add", ".")
    git!("commit", "-qm", "Publish catalog after release")
    current_identity = Logister::ReleaseIdentity.new(repo_root: repo_root).validate!
    expect(current_identity.contract_sha256).not_to eq(identity.contract_sha256)

    receipt = described_class.new(repo_root: repo_root, release_set_path: release_set_path, http: FakeHttp.new(responses)).reconcile

    expect(receipt.fetch(:status)).to eq("complete")
    expect(receipt.dig(:backend, :contract_sha256)).to eq(identity.contract_sha256)
    expect(receipt.dig(:backend, :git_sha)).to eq(release_sha)
  end

  it "rejects a receipt and runtime using current main's hashes instead of the release tag" do
    hashes = Logister::ReleaseIdentity.new(repo_root: repo_root).validate!.contract_sha256
    [ receipt_url, "https://logister.org/health/release" ].each do |url|
      payload = JSON.parse(responses.fetch(url).last)
      responses[url] = ok_json(payload.merge("contract_sha256" => hashes))
    end

    receipt = described_class.new(repo_root: repo_root, release_set_path: release_set_path, http: FakeHttp.new(responses)).reconcile

    expect(receipt.fetch(:status)).to eq("pending")
    expect(receipt.fetch(:errors)).to include("backend/release_receipt: receipt contract mismatch", "backend/runtime: runtime contract mismatch")
  end

  it "rejects matching receipt and runtime commits that do not match the release tag" do
    [ receipt_url, "https://logister.org/health/release" ].each do |url|
      payload = JSON.parse(responses.fetch(url).last)
      responses[url] = ok_json(payload.merge("git_sha" => "b" * 40))
    end

    receipt = described_class.new(repo_root: repo_root, release_set_path: release_set_path, http: FakeHttp.new(responses)).reconcile

    expect(receipt.fetch(:status)).to eq("pending")
    expect(receipt.fetch(:errors)).to include("backend/release_receipt: receipt Git SHA does not match release tag", "backend/runtime: runtime Git SHA mismatch")
  end

  it "fails closed when the release tag is missing" do
    git!("tag", "--delete", "v3.6")
    reconciler = described_class.new(repo_root: repo_root, release_set_path: release_set_path, http: FakeHttp.new(responses))

    expect { reconciler.reconcile }.to raise_error(Logister::ReleaseSet::ValidationError, /fetch release tags/)
  end

  it "rejects a tag whose source declares another version" do
    git!("tag", "--delete", "v3.6")
    git!("tag", "v3.6")
    reconciler = described_class.new(repo_root: repo_root, release_set_path: release_set_path, http: FakeHttp.new(responses))

    expect { reconciler.reconcile }.to raise_error(Logister::ReleaseSet::ValidationError, /does not match its source version/)
  end

  it "does not create a verified catalog from an incomplete release set" do
    responses[maven_url] = [ 404, "" ]
    reconciler = described_class.new(repo_root: repo_root, release_set_path: release_set_path, http: FakeHttp.new(responses))
    receipt = reconciler.reconcile

    expect { reconciler.catalog(receipt) }.to raise_error("release set is not complete")
  end

  it "refuses to download a CLI npm tarball from a non-canonical URL" do
    rogue_url = "https://evil.example/logister-cli-1.0.0.tgz"
    responses["https://registry.npmjs.org/logister-cli/1.0.0"] = ok_json(
      version: "1.0.0",
      dist: { tarball: rogue_url, shasum: Digest::SHA1.hexdigest(tarball) }
    )
    http = FakeHttp.new(responses)
    allow(http).to receive(:get).and_call_original

    receipt = described_class.new(repo_root: repo_root, release_set_path: release_set_path, http: http).reconcile

    expect(receipt.fetch(:status)).to eq("pending")
    expect(receipt.fetch(:errors)).to include("logister-cli/npm: CLI npm tarball URL is not canonical")
    expect(http).not_to have_received(:get).with(rogue_url)
  end

  it "requires both Android artifacts from 0.6.0 onward" do
    version = "0.6.0"
    root = "https://repo1.maven.org/maven2/org/logister"
    urls = %w[logister-android logister-android-okhttp].flat_map do |artifact|
      %w[pom aar].map { |ext| "#{root}/#{artifact}/#{version}/#{artifact}-#{version}.#{ext}" }
    end
    values = urls.to_h { |url| [ url, [ 200, url.end_with?("aar") ? "PKsynthetic-archive" : "<artifactId>logister-android-okhttp</artifactId><version>0.6.0</version>" ] ] }
    values.delete(urls.last)
    reconciler = described_class.new(repo_root: repo_root, release_set_path:, http: FakeHttp.new(values))
    reconciler.send(:reconcile_channel, "logister-android", "maven_central", version)
    expect(reconciler.send(:errors)).to include(match(/public endpoint returned HTTP 404/))
    values[urls.last] = [ 200, "PKsynthetic-archive" ]
    complete = described_class.new(repo_root: repo_root, release_set_path:, http: FakeHttp.new(values))
    complete.send(:reconcile_channel, "logister-android", "maven_central", version)
    expect(complete.send(:errors)).to be_empty
  end

  def public_responses
    release_set = YAML.safe_load_file(release_set_path, permitted_classes: [], permitted_symbols: [], aliases: false)
    values = {}
    values[github_release_url("taimoorq/logister", "v3.6")] = ok_json(
      tag_name: "v3.6",
      draft: false,
      assets: [ { name: "release-receipt.json", browser_download_url: receipt_url } ]
    )
    values[receipt_url] = ok_json(
      version: "3.6",
      tag: "v3.6",
      git_sha: release_sha,
      contract_sha256: identity.contract_sha256,
      container: {
        digest: "sha256:#{"a" * 64}",
        registries: {
          docker_hub: "docker.io/taimoorq/logister:v3.6",
          ghcr: "ghcr.io/taimoorq/logister:v3.6"
        }
      },
      deployment: { provider: "fly", verified: true }
    )
    values["https://logister.org/health/release"] = ok_json(
      status: "ok",
      version: "3.6",
      tag: "v3.6",
      git_sha: release_sha,
      image_digest: "sha256:#{"a" * 64}",
      contract_sha256: identity.contract_sha256,
      database: { connected: true, migrations_current: true }
    )

    release_set.fetch("components").each do |_id, component|
      version = component.fetch("target_version")
      values[github_release_url(component.fetch("repository"), "v#{version}")] = ok_json(tag_name: "v#{version}", draft: false, assets: [])
    end
    values["https://rubygems.org/api/v1/versions/logister-ruby.json"] = ok_json([ { number: "0.4.0" } ])
    values["https://registry.npmjs.org/logister-js/0.4.1"] = ok_json(version: "0.4.1")
    values["https://pypi.org/pypi/logister-python/0.3.1/json"] = ok_json(info: { version: "0.3.1" })
    values["https://api.nuget.org/v3-flatcontainer/logister/index.json"] = ok_json(versions: [ "0.2.1" ])
    values["https://api.nuget.org/v3-flatcontainer/logister.aspnetcore/index.json"] = ok_json(versions: [ "0.2.1" ])
    values[maven_url] = [ 200, "<project><version>0.4.0</version></project>" ]
    values["https://registry.npmjs.org/logister-cli/1.0.0"] = ok_json(
      version: "1.0.0",
      dist: { tarball: tarball_url, shasum: Digest::SHA1.hexdigest(tarball) }
    )
    values[tarball_url] = [ 200, tarball ]
    sha256 = Digest::SHA256.hexdigest(tarball)
    values["https://raw.githubusercontent.com/taimoorq/homebrew-logister/main/Formula/logister.rb"] = [
      200,
      "  url \"#{tarball_url}\"\n  sha256 \"#{sha256}\"\n"
    ]
    values["https://raw.githubusercontent.com/taimoorq/scoop-logister/main/bucket/logister.json"] = ok_json(
      version: "1.0.0",
      url: tarball_url,
      hash: sha256
    )
    values
  end

  def github_release_url(repository, tag)
    "https://api.github.com/repos/#{repository}/releases/tags/#{tag}"
  end

  def receipt_url
    "https://github.com/taimoorq/logister/releases/download/v3.6/release-receipt.json"
  end

  def prepare_released_source
    ecosystem = YAML.safe_load_file(Rails.root.join("config/ecosystem.yml"))
    release_set = YAML.safe_load_file(Rails.root.join("config/release-sets/v3.6.yml"))
    files = %w[VERSION CHANGELOG.md config/release.yml config/ecosystem.yml config/ecosystem-versions.json config/release-sets/v3.6.yml]
    files.concat(ecosystem.fetch("contracts").values.flat_map { |contract| contract.fetch("source_files") })
    files.concat(release_set.fetch("impact_records").map { |id| "config/release-impact/#{id}.yml" })
    files.uniq.each do |path|
      FileUtils.mkdir_p(repo_root.join(path).dirname)
      FileUtils.cp(Rails.root.join(path), repo_root.join(path))
    end
    repo_root.join("VERSION").write("3.6\n")
    repo_root.join("CHANGELOG.md").write("# Changelog\n\n## v3.6 - 2026-08-09\n\n- Public release.\n")
    openapi = YAML.safe_load_file(repo_root.join("docs/openapi.yaml"))
    openapi.fetch("info")["version"] = "3.6"
    repo_root.join("docs/openapi.yaml").write(YAML.dump(openapi))

    git!("init", "-q")
    git!("config", "user.name", "Release Test")
    git!("config", "user.email", "release-test@example.invalid")
    git!("add", ".")
    git!("-c", "commit.gpgsign=false", "commit", "-qm", "Released backend")
    git!("-c", "tag.gpgsign=false", "tag", "--annotate", "v3.6", "--message", "Released backend")
    @release_sha = git!("rev-parse", "HEAD").strip
    @released_identity = Logister::ReleaseIdentity.new(repo_root: repo_root).validate!

    %w[VERSION CHANGELOG.md docs/openapi.yaml].each do |path|
      FileUtils.cp(Rails.root.join(path), repo_root.join(path))
    end
    git!("add", ".")
    git!("-c", "commit.gpgsign=false", "commit", "-qm", "Advance current source")
  end

  def git!(*arguments)
    output, error, status = Open3.capture3("git", "-C", repo_root.to_s, *arguments)
    raise error unless status.success?

    output
  end

  def maven_url
    "https://repo1.maven.org/maven2/org/logister/logister-android/0.4.0/logister-android-0.4.0.pom"
  end

  def ok_json(value)
    [ 200, JSON.generate(value) ]
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ReleaseSetReconciler do
  FakeHttp = Struct.new(:responses) do
    def get(url)
      responses.fetch(url, [ 404, "" ])
    end
  end

  let(:release_set_path) { Rails.root.join("config/release-sets/v3.6.yml") }
  let(:identity) { Logister::ReleaseIdentity.new(repo_root: Rails.root).validate! }
  let(:tarball) { "canonical CLI npm tarball bytes" }
  let(:tarball_url) { "https://registry.npmjs.org/logister-cli/-/logister-cli-1.0.0.tgz" }
  let(:responses) { public_responses }

  it "reconciles the backend and every package channel into a public receipt" do
    reconciler = described_class.new(repo_root: Rails.root, release_set_path: release_set_path, http: FakeHttp.new(responses))
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
    receipt = described_class.new(repo_root: Rails.root, release_set_path: release_set_path, http: FakeHttp.new(responses)).reconcile

    expect(receipt.fetch(:status)).to eq("pending")
    expect(receipt.fetch(:errors)).to include(match(%r{logister-android/maven_central: public endpoint returned HTTP 404}))
    expect(receipt.fetch(:checks)).to include(
      component: "logister-android",
      channel: "maven_central",
      url: maven_url,
      status: "pending"
    )
  end

  it "does not create a verified catalog from an incomplete release set" do
    responses[maven_url] = [ 404, "" ]
    reconciler = described_class.new(repo_root: Rails.root, release_set_path: release_set_path, http: FakeHttp.new(responses))
    receipt = reconciler.reconcile

    expect { reconciler.catalog(receipt) }.to raise_error("release set is not complete")
  end

  def public_responses
    release_set = YAML.safe_load_file(release_set_path, permitted_classes: [], permitted_symbols: [], aliases: false)
    values = {}
    receipt_url = "https://github.com/taimoorq/logister/releases/download/v3.6/release-receipt.json"
    values[github_release_url("taimoorq/logister", "v3.6")] = ok_json(
      tag_name: "v3.6",
      draft: false,
      assets: [ { name: "release-receipt.json", browser_download_url: receipt_url } ]
    )
    values[receipt_url] = ok_json(
      version: "3.6",
      tag: "v3.6",
      git_sha: "b" * 40,
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
      git_sha: "b" * 40,
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

  def maven_url
    "https://repo1.maven.org/maven2/org/logister/logister-android/0.4.0/logister-android-0.4.0.pom"
  end

  def ok_json(value)
    [ 200, JSON.generate(value) ]
  end
end

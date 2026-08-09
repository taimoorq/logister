# frozen_string_literal: true

require "rails_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Logister::ReleaseIdentity do
  it "derives one version, release note, and digest set from public sources" do
    identity = described_class.new(repo_root: Rails.root).validate!

    expect(identity).to have_attributes(
      version: "3.6",
      tag: "v3.6",
      release_date: "2026-08-09",
      prerelease: false,
      make_latest: true
    )
    expect(identity.release_notes).to start_with("## v3.6 - 2026-08-09")
    expect(identity.release_notes).not_to include("## v3.5")
    expect(identity.contract_sha256.keys).to contain_exactly("cli_api", "telemetry_ingest", "integration_discovery")
    expect(identity.contract_sha256.values).to all(match(/\A[0-9a-f]{64}\z/))
  end

  it "rejects drift between VERSION and the changelog" do
    with_release_fixture(version: "3.7", changelog_version: "3.6", openapi_version: "3.7") do |root|
      expect { described_class.new(repo_root: root).validate! }
        .to raise_error(described_class::ValidationError, /does not match the first changelog release/)
    end
  end

  it "rejects drift between VERSION and OpenAPI" do
    with_release_fixture(version: "3.7", changelog_version: "3.7", openapi_version: "3.6") do |root|
      expect { described_class.new(repo_root: root).validate! }
        .to raise_error(described_class::ValidationError, /OpenAPI info.version/)
    end
  end

  it "requires a full immutable release commit" do
    checker = described_class.new(repo_root: Rails.root)

    expect(checker.validate_git_sha!("a" * 40)).to eq("a" * 40)
    expect { checker.validate_git_sha!("05705e9") }
      .to raise_error(described_class::ValidationError, /full lowercase 40-character/)
  end

  def with_release_fixture(version:, changelog_version:, openapi_version:)
    Dir.mktmpdir("logister-release-identity") do |directory|
      root = Pathname(directory)
      FileUtils.mkdir_p(root.join("config"))
      FileUtils.mkdir_p(root.join("docs"))
      root.join("VERSION").write("#{version}\n")
      root.join("CHANGELOG.md").write("# Changelog\n\n## v#{changelog_version} - 2026-08-09\n\n- Public note.\n")
      root.join("docs/openapi.yaml").write("openapi: 3.1.0\ninfo:\n  version: '#{openapi_version}'\n")
      root.join("docs/contract.json").write("{}\n")
      root.join("config/release.yml").write(<<~YAML)
        tag_prefix: v
        version_path: VERSION
        changelog_path: CHANGELOG.md
        github:
          make_latest: true
      YAML
      root.join("config/ecosystem.yml").write(<<~YAML)
        schema_version: 1
        backend:
          version_source:
            path: VERSION
            format: plain_text
        contracts:
          example:
            source_files:
              - docs/contract.json
      YAML
      yield root
    end
  end
end

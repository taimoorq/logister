# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Logister::ReleaseSet do
  let(:release_set_path) { Rails.root.join("config/release-sets/v3.6.yml") }

  it "keeps a historical release set structurally valid after VERSION advances" do
    release_set = described_class.new(repo_root: Rails.root, release_set_path: release_set_path).validate!

    expect(release_set.dig("backend", "version")).to eq("3.6")
  end

  it "validates every ecosystem component and its independent target version" do
    release_set = described_class.new(repo_root: Rails.root, release_set_path: release_set_path).validate!

    expect(release_set.dig("backend", "version")).to eq("3.6")
    expect(release_set.fetch("components").keys).to match_array(YAML.safe_load_file(Rails.root.join("config/ecosystem.yml")).fetch("addons").keys)
    expect(release_set.dig("components", "logister-android")).to include(
      "baseline_version" => "0.3.0",
      "target_version" => "0.4.0",
      "bump" => "minor",
      "release_required" => true
    )
  end

  it "rejects a target that does not match its declared bump" do
    with_release_set("logister-android", "target_version", "0.3.1") do |path|
      expect { described_class.new(repo_root: Rails.root, release_set_path: path).validate! }
        .to raise_error(described_class::ValidationError, /is not a minor bump/)
    end
  end

  it "requires every version change to be released" do
    with_release_set("logister-js", "release_required", false) do |path|
      expect { described_class.new(repo_root: Rails.root, release_set_path: path).validate! }
        .to raise_error(described_class::ValidationError, /changes version but is not release_required/)
    end
  end

  it "rejects local paths and credential material from public release metadata" do
    local_path = "Read /#{"Users"}/example/private release notes for "
    fake_credential = "github_#{"pat"}_abcdefghijklmnopqrstuvwxyz123456"
    with_release_set("logister-ios", "reason", "#{local_path}#{fake_credential}") do |path|
      expect { described_class.new(repo_root: Rails.root, release_set_path: path).validate! }
        .to raise_error(described_class::ValidationError, /credential|local user path/)
    end
  end

  def with_release_set(component, key, value)
    release_set = YAML.safe_load_file(release_set_path, permitted_classes: [], permitted_symbols: [], aliases: false)
    release_set.fetch("components").fetch(component)[key] = value
    Dir.mktmpdir("logister-release-set") do |directory|
      path = Pathname(directory).join("release-set.yml")
      path.write(YAML.dump(release_set))
      yield path
    end
  end
end

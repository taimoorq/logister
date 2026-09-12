# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "fileutils"

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

  it "does not compare historical targets with a later published catalog" do
    with_catalog("logister-android", "99.0.0") do |root|
      expect { described_class.new(repo_root: root, release_set_path: release_set_path).validate! }.not_to raise_error
    end
  end

  it "rejects a published add-on outside the current release set" do
    with_catalog("logister-android", "99.0.0") do |root|
      path = Rails.root.join("config/release-sets/v#{Rails.root.join('VERSION').read.strip}.yml")
      expect { described_class.new(repo_root: root, release_set_path: path).validate! }
        .to raise_error(described_class::ValidationError, /Published logister-android version .* is outside this release set/)
    end
  end

  it "rejects a published backend newer than the current release target" do
    with_catalog("backend", "99.0.0") do |root|
      path = Rails.root.join("config/release-sets/v#{Rails.root.join('VERSION').read.strip}.yml")
      expect { described_class.new(repo_root: root, release_set_path: path).validate! }
        .to raise_error(described_class::ValidationError, /Published backend version .* is invalid for target/)
    end
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

  def with_catalog(component, version)
    Dir.mktmpdir("logister-release-catalog") do |directory|
      root = Pathname(directory)
      FileUtils.cp(Rails.root.join("VERSION"), root.join("VERSION"))
      FileUtils.mkdir_p(root.join("config"))
      %w[ecosystem.yml ecosystem-versions.json release-impact].each do |entry|
        FileUtils.cp_r(Rails.root.join("config", entry), root.join("config", entry))
      end
      path = root.join("config/ecosystem-versions.json")
      catalog = JSON.parse(path.read)
      entry = component == "backend" ? catalog.fetch("backend") : catalog.fetch("addons").fetch(component)
      entry["version"] = version
      path.write(JSON.generate(catalog))
      yield root
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

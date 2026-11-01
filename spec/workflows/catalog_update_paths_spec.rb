# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

RSpec.describe "Catalog update path validation" do
  let(:workflow) do
    YAML.safe_load_file(Pathname.new(__dir__).join("../../.github/workflows/release-set-reconcile.yml"), aliases: true)
  end
  let(:steps) { workflow.fetch("jobs").fetch("reconcile").fetch("steps") }
  let(:validation_script) { steps.find { |step| step["name"] == "Validate catalog update paths" }.fetch("run") }

  def validate_changes(paths)
    Dir.mktmpdir("catalog-update-paths-") do |directory|
      system("git", "init", "--quiet", directory, exception: true)
      FileUtils.mkdir_p(File.join(directory, "config/release-sets"))
      File.write(File.join(directory, "config/release-sets/v4.1.0.yml"), YAML.dump("impact_records" => [ "current-release" ]))
      paths.each do |path|
        file = File.join(directory, path)
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, "before\n")
      end
      system("git", "-C", directory, "add", ".", exception: true)
      paths.each { |path| File.write(File.join(directory, path), "after\n") }

      Open3.capture3({ "RELEASE_SET_PATH" => "config/release-sets/v4.1.0.yml" }, "bash", "-c", validation_script, chdir: directory)
    end
  end

  it "accepts the Markdown mobile guide and the other generated catalog surfaces" do
    paths = %w[
      config/ecosystem-versions.json README.md public/llms.txt public/llms-full.txt
      docs/mobile-add-ons.md docs/openapi.yaml app/services/logister/cli_capabilities.rb
      spec/requests/api/v1/cli_capabilities_spec.rb app/views/home/index.html.erb
      cloudflare-docs/docs/mobile/index.html cloudflare-docs/llms-full.txt
      config/release-impact/current-release.yml
    ]
    stdout, stderr, status = validate_changes(paths)

    expect(status).to be_success, "#{stdout}\n#{stderr}"
  end

  %w[docs/mobile-add-ons.yaml app/controllers/projects_controller.rb .github/workflows/release.yml config/release-impact/unrelated-release.yml].each do |path|
    it "rejects unrelated changes to #{path} even alongside the mobile guide" do
      _stdout, stderr, status = validate_changes([ "docs/mobile-add-ons.md", path ])

      expect(status).not_to be_success
      expect(stderr).to include("Catalog sync attempted to modify unsupported files:", path)
    end
  end

  it "lets the catalog bot supply Git credentials instead of persisting the checkout token" do
    checkout = steps.find { |step| step["name"] == "Check out public release metadata" }

    expect(checkout.fetch("with").fetch("persist-credentials")).to be(false)
  end

  it "refreshes discovery evidence while preserving the reviewed release decisions" do
    root = Pathname.new(__dir__).join("../..").expand_path
    refresh_script = steps.find { |step| step["name"] == "Refresh catalog release-impact evidence" }.fetch("run")
    version = root.join("VERSION").read.strip
    release_set_path = "config/release-sets/v#{version}.yml"
    release_set = YAML.safe_load_file(root.join(release_set_path))
    impact_paths = release_set.fetch("impact_records").map { |id| "config/release-impact/#{id}.yml" }
    sources = YAML.safe_load_file(root.join("config/ecosystem.yml")).fetch("contracts").values.flat_map { |contract| contract.fetch("source_files") }
    fixture_paths = [ "VERSION", release_set_path, "lib/logister/release_impact.rb", "bin/check-release-impact", *sources, *impact_paths ].uniq

    Dir.mktmpdir("catalog-impact-") do |directory|
      fixture_paths.each do |path|
        FileUtils.mkdir_p(File.dirname(File.join(directory, path)))
        FileUtils.cp(root.join(path), File.join(directory, path), preserve: true)
      end
      original_records = impact_paths.to_h { |path| [ path, YAML.safe_load_file(File.join(directory, path)) ] }
      mobile_guide = File.join(directory, "docs/mobile-add-ons.md")
      File.write(mobile_guide, File.read(mobile_guide).gsub(/(?<=logister-android:)\d+\.\d+\.\d+/) do |version_text|
        parts = version_text.split(".")
        parts[-1] = parts[-1].to_i.succ.to_s
        parts.join(".")
      end)
      env = { "RELEASE_SET_PATH" => release_set_path }
      stdout, stderr, status = Open3.capture3(env, "bash", "-c", refresh_script, chdir: directory)

      expect(status).to be_success, "#{stdout}\n#{stderr}"
      original_records.each do |path, original|
        updated = YAML.safe_load_file(File.join(directory, path))
        expect(updated.except("contract_sha256")).to eq(original.except("contract_sha256"))
        expect(updated.fetch("contract_sha256").except("integration_discovery")).to eq(original.fetch("contract_sha256").except("integration_discovery"))
        if original.fetch("contracts").include?("integration_discovery")
          expect(updated.dig("contract_sha256", "integration_discovery")).not_to eq(original.dig("contract_sha256", "integration_discovery"))
        else
          expect(updated).to eq(original)
        end
      end

      first_run = impact_paths.to_h { |path| [ path, File.read(File.join(directory, path)) ] }
      _stdout, stderr, status = Open3.capture3(env, "bash", "-c", refresh_script, chdir: directory)
      expect(status).to be_success, stderr
      expect(impact_paths.to_h { |path| [ path, File.read(File.join(directory, path)) ] }).to eq(first_run)
    end
  end
end

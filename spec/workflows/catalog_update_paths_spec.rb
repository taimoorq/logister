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
      paths.each do |path|
        file = File.join(directory, path)
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, "before\n")
      end
      system("git", "-C", directory, "add", ".", exception: true)
      paths.each { |path| File.write(File.join(directory, path), "after\n") }

      Open3.capture3("bash", "-c", validation_script, chdir: directory)
    end
  end

  it "accepts the Markdown mobile guide and the other generated catalog surfaces" do
    paths = %w[
      config/ecosystem-versions.json README.md public/llms.txt public/llms-full.txt
      docs/mobile-add-ons.md docs/openapi.yaml app/services/logister/cli_capabilities.rb
      spec/requests/api/v1/cli_capabilities_spec.rb app/views/home/index.html.erb
      cloudflare-docs/docs/mobile/index.html cloudflare-docs/llms-full.txt
    ]
    stdout, stderr, status = validate_changes(paths)

    expect(status).to be_success, "#{stdout}\n#{stderr}"
  end

  %w[docs/mobile-add-ons.yaml app/controllers/projects_controller.rb .github/workflows/release.yml].each do |path|
    it "rejects unrelated changes to #{path} even alongside the mobile guide" do
      stdout, _stderr, status = validate_changes([ "docs/mobile-add-ons.md", path ])

      expect(status).not_to be_success
      expect(stdout).to include("Catalog sync attempted to modify unsupported files:", path)
    end
  end

  it "lets the catalog bot supply Git credentials instead of persisting the checkout token" do
    checkout = steps.find { |step| step["name"] == "Check out public release metadata" }

    expect(checkout.fetch("with").fetch("persist-credentials")).to be(false)
  end
end

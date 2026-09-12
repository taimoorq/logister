# frozen_string_literal: true

require "spec_helper"
require "open3"
require_relative "../../../lib/logister/backend_release_changes"

RSpec.describe Logister::BackendReleaseChanges do
  it "allows the public catalog and static documentation to follow an immutable release" do
    paths = %w[config/ecosystem-versions.json cloudflare-docs/integrations/ruby/index.html
      cloudflare-docs/sitemap.xml public/llms.txt public/llms-full.txt README.md docs/mobile-add-ons.md]

    expect(described_class.publishable(paths)).to be_empty
  end

  it "requires a version for runtime code, configuration, dependencies and release identities" do
    paths = %w[app/services/logister/cli_capabilities.rb app/views/docs/index.html.erb
      config/routes.rb config/ecosystem-versions.json.backup config/ecosystem.yml.rb
      config/release-sets/v3.6.12.yml lib/logister/release_set.rb public/runtime.js
      public/llms.txt.rb .env.sample Gemfile.lock VERSION Dockerfile]

    expect(described_class.publishable(paths)).to eq(paths)
  end

  it "uses this classification in the actual tag workflow" do
    require "yaml"
    root = File.expand_path("../../..", __dir__)
    workflow = YAML.safe_load_file(File.join(root, ".github/workflows/release-from-main.yml"), aliases: true)
    step = workflow.fetch("jobs").fetch("tag").fetch("steps").find { |entry| entry["id"] == "tag_state" }
    program = step.fetch("run").match(/\| ruby -e '(.*?)'\)/m).captures.first
    output, error, status = Open3.capture3("ruby", "-e", program,
      stdin_data: "config/ecosystem-versions.json\ncloudflare-docs/index.html\napp/services/logister/cli_capabilities.rb\n", chdir: root)

    expect(status).to be_success, error
    expect(output.lines(chomp: true)).to eq([ "app/services/logister/cli_capabilities.rb" ])
  end
end

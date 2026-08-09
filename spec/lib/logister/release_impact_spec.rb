# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "yaml"

RSpec.describe Logister::ReleaseImpact do
  subject(:validate) do
    described_class.new(
      ecosystem_path: Rails.root.join("config/ecosystem.yml"),
      impact_paths: impact_paths,
      changed_files: changed_files
    ).validate!
  end

  let(:changed_files) { [ "app/services/ingest_event_payload_normalizer.rb" ] }
  let(:impact_paths) { [ impact_path ] }
  let(:impact) do
    {
      "schema_version" => 1,
      "id" => "telemetry-evidence-contract",
      "summary" => "Add a compatible telemetry evidence envelope.",
      "backend" => {
        "bump" => "minor",
        "compatibility" => "expand",
        "activation" => "backend_first_dark"
      },
      "contracts" => [ "telemetry_ingest" ],
      "contract_sha256" => {
        "telemetry_ingest" => contract_digest("telemetry_ingest")
      },
      "consumers" => telemetry_consumer_decisions
    }
  end
  let(:telemetry_consumer_decisions) do
    %w[
      logister-ruby logister-js logister-python logister-dotnet logister-android logister-ios
    ].to_h do |consumer|
      [ consumer, { "bump" => "none", "reason" => "The existing payload remains compatible for this consumer." } ]
    end
  end

  around do |example|
    Dir.mktmpdir("release-impact-spec") do |directory|
      @impact_path = Pathname(directory).join("impact.yml")
      example.run
    end
  end

  def impact_path
    @impact_path.tap { |path| path.write(YAML.dump(impact)) }
  end

  def contract_digest(contract)
    ecosystem = YAML.safe_load_file(Rails.root.join("config/ecosystem.yml"), aliases: false)
    described_class.contract_digest(
      repo_root: Rails.root,
      paths: ecosystem.dig("contracts", contract, "source_files")
    )
  end

  it "accepts an explicit decision for every consumer of a changed contract" do
    result = validate

    expect(result.triggered_contracts).to eq([ "telemetry_ingest" ])
    expect(result.consumer_decisions.keys).to contain_exactly(
      "logister-ruby", "logister-js", "logister-python", "logister-dotnet", "logister-android", "logister-ios"
    )
  end

  it "requires a release-impact record for a release-sensitive change" do
    expect do
      described_class.new(
        ecosystem_path: Rails.root.join("config/ecosystem.yml"),
        impact_paths: [],
        changed_files: changed_files
      ).validate!
    end.to raise_error(described_class::ValidationError, /no changed config\/release-impact/)
  end

  it "requires every contract consumer to have an explicit decision" do
    telemetry_consumer_decisions.delete("logister-ios")

    expect { validate }.to raise_error(described_class::ValidationError, /requires explicit decisions for: logister-ios/)
  end

  it "rejects unsupported bump classes and short reasons" do
    telemetry_consumer_decisions["logister-ios"] = { "bump" => "feature", "reason" => "no" }

    expect { validate }.to raise_error(described_class::ValidationError) do |error|
      expect(error.errors).to include(
        a_string_matching(/logister-ios bump is invalid/),
        a_string_matching(/logister-ios reason must be 12\.\.500/)
      )
    end
  end

  it "rejects secrets and local user paths from public release metadata" do
    local_path = File.join("/", "Users", "example", "private-notes")
    fake_credential = "github_#{"pat"}_#{"a" * 26}"
    impact["summary"] = "Read #{local_path} and use ?token=#{fake_credential}."

    expect { validate }.to raise_error(described_class::ValidationError) do |error|
      expect(error.errors).to include(
        a_string_matching(/GitHub credential/),
        a_string_matching(/credential-bearing URL/),
        a_string_matching(/local user path/)
      )
    end
  end

  it "rejects consumers absent from the ecosystem registry" do
    impact["consumers"]["private-addon"] = {
      "bump" => "patch",
      "reason" => "This repository is not part of the public ecosystem."
    }

    expect { validate }.to raise_error(described_class::ValidationError, /unknown consumers: private-addon/)
  end

  it "rejects duplicate release-impact identifiers" do
    duplicate_path = impact_path.dirname.join("duplicate.yml")
    duplicate_path.write(YAML.dump(impact))
    impact_paths << duplicate_path

    expect { validate }.to raise_error(described_class::ValidationError, /id "telemetry-evidence-contract" is duplicated/)
  end

  it "rejects a stale contract digest" do
    impact["contract_sha256"]["telemetry_ingest"] = "0" * 64

    expect { validate }.to raise_error(described_class::ValidationError, /contract_sha256.telemetry_ingest is stale/)
  end

  it "validates the ecosystem manifest without requiring an impact record when no sensitive path changed" do
    result = described_class.new(
      ecosystem_path: Rails.root.join("config/ecosystem.yml"),
      impact_paths: [],
      changed_files: [ "app/views/home/index.html.erb" ]
    ).validate!

    expect(result.triggered_contracts).to be_empty
  end

  it "rejects revision arguments that could be interpreted as Git options or shell input" do
    expect(Open3).not_to receive(:capture3)

    expect do
      described_class.changed_files(repo_root: Rails.root, base: "--output=/tmp/changed", head: "HEAD; touch /tmp/pwned")
    end.to raise_error(described_class::ValidationError, /Git references must use/)
  end
end

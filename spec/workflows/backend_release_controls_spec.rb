# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "Backend release workflow controls" do
  let(:ci_path) { Rails.root.join(".github/workflows/ci.yml") }
  let(:from_main_path) { Rails.root.join(".github/workflows/release-from-main.yml") }
  let(:release_path) { Rails.root.join(".github/workflows/release.yml") }
  let(:dispatch_path) { Rails.root.join(".github/workflows/addon-release-dispatch.yml") }
  let(:reconcile_path) { Rails.root.join(".github/workflows/release-set-reconcile.yml") }

  it "keeps deployment out of the ordinary CI workflow" do
    jobs = YAML.safe_load_file(ci_path, aliases: true).fetch("jobs")

    expect(jobs).to include("ci_passed")
    expect(jobs).not_to include("deploy")
  end

  it "allows only the successful current main commit to create a version tag" do
    workflow = from_main_path.read

    expect(workflow).to include("github.event.workflow_run.conclusion == 'success'")
    expect(workflow).to include('main_sha="$(git rev-parse origin/main)"')
    expect(workflow).to include("publishable changes without a new VERSION")
    expect(workflow).to include('git tag --annotate "${RELEASE_TAG}"')
    expect(workflow).to include("gh workflow run release.yml")
  end

  it "builds one canonical digest and promotes that digest everywhere" do
    workflow = release_path.read

    expect(workflow.scan("uses: docker/build-push-action@v7").length).to eq(1)
    expect(workflow).to include('CANONICAL_REFERENCE: ${{ steps.canonical.outputs.reference }}')
    expect(workflow).to include('docker buildx imagetools create --tag "${target}" "${CANONICAL_REFERENCE}"')
    expect(workflow).to include('--image "${CANONICAL_REFERENCE}"')
    expect(workflow).to include("Verify registries are publicly readable")
    expect(workflow).to include("Verify public runtime release identity")
    expect(workflow).to include("release-receipt.json")
    expect(workflow).not_to include("Skip already-published release")
  end

  it "bakes the version and full revision into the published image" do
    dockerfile = Rails.root.join("Dockerfile").read

    expect(dockerfile).to include("ARG LOGISTER_VERSION")
    expect(dockerfile).to include("ARG LOGISTER_GIT_SHA")
    expect(dockerfile).to include('LOGISTER_RELEASE="${LOGISTER_VERSION}"')
    expect(dockerfile).to include('LOGISTER_GIT_SHA="${LOGISTER_GIT_SHA}"')
  end

  it "dispatches only checksum-pinned release-required add-ons after CI" do
    workflow = dispatch_path.read

    expect(workflow).to include("github.event.workflow_run.conclusion == 'success'")
    expect(workflow).to include('next unless metadata.fetch("release_required")')
    expect(workflow).to include("release_set_sha256: checksum")
    expect(workflow).to include('event_type: "logister-release-impact"')
    expect(workflow).to include("LOGISTER_ADDON_RELEASE_TOKEN")
  end

  it "keeps release completion pending until public channels and the catalog agree" do
    workflow = reconcile_path.read

    expect(workflow).to include("bin/reconcile-release-set")
    expect(workflow).to include("Verify every recorded container reference anonymously")
    expect(workflow).to include('context="release/ecosystem"')
    expect(workflow).to include('CATALOG_CHANGED: ${{ steps.catalog.outputs.changed }}')
    expect(workflow).to include("LOGISTER_CATALOG_BOT_TOKEN")
    expect(workflow).to include("Keep non-terminal release set pending")
  end

  it "syncs public docs only from the verified committed catalog" do
    sync = Rails.root.join("bin/sync-doc-versions").read

    expect(sync).to include('config/ecosystem-versions.json')
    expect(sync).not_to include("LOGISTER_WORKSPACE_ROOT")
    expect(sync).not_to include("read_companion_text")
  end
end

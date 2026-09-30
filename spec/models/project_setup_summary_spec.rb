# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectSetupSummary do
  def make_live(project)
    key = create(:api_key, project: project, user: project.user)
    create(:ingest_event, project: project, api_key: key)
  end

  it "is incomplete until every required step has evidence, and names what it is waiting on" do
    project = create(:project, :ruby)

    summary = described_class.for(project)
    expect(summary.state).to eq(:incomplete)
    expect(summary.live?).to be(false)
    expect(summary.focus.chip_label).to eq("Create an API key")

    create(:api_key, project: project, user: project.user)
    expect(described_class.for(project).focus.chip_label).to eq("Waiting for first event")
  end

  it "uses the type's own wording while waiting" do
    android = create(:project, :android)
    expect(described_class.for(android).focus.chip_label).to eq("Issue a mobile token")
  end

  it "is live with a count of recommended steps the viewer could do" do
    project = create(:project, :ruby)
    make_live(project)

    summary = described_class.for(project)
    expect(summary.state).to eq(:live_with_steps)
    expect(summary.live?).to be(true)
    expect(summary.open_recommended).to be_positive
  end

  it "stays quiet once nothing is left to do" do
    project = create(:project, :ruby)
    make_live(project)
    allow(Logister::GithubAppConfig).to receive(:configured?).and_return(true)
    ProjectSetupCatalog.steps_for(:server).reject { |step| step.group.required? || step.personal }.each do |step|
      project.setup_steps.create!(key: step.key.to_s, decided_by_user: project.user)
    end

    summary = described_class.for(project)
    expect(summary.quiet?).to be(true)
    expect(summary.state).to eq(:live)
  end

  it "does not count steps that wait on an instance setting, so they do not nag every project" do
    project = create(:project, :ruby)
    make_live(project)
    allow(Logister::GithubAppConfig).to receive(:configured?).and_return(false)

    plan = ProjectSetupPlan.for(project)
    expect(plan.item(:source_repo).state).to eq(:blocked)
    expect(described_class.for(project).open_recommended).to eq(plan.open_recommended_items.size)
    expect(plan.open_recommended_items.map(&:key)).not_to include(:source_repo)
  end

  it "raises a failing or stale configured integration above everything else" do
    project = create(:project, :android)
    setting = create(
      :project_integration_setting, project: project, provider: "google_play", enabled: true,
      external_project_id: "com.acme.shop", credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS",
      last_imported_at: 2.days.ago
    )
    setting.update!(metadata: { "last_error" => { "message" => "denied", "at" => Time.current.utc.iso8601 } })

    summary = described_class.for(project)
    expect(summary.state).to eq(:attention)
    expect(summary.attention.chip_label).to eq("Google Play failed")
  end

  it "does not depend on who is looking, so one cached summary serves everyone" do
    project = create(:project, :ruby)
    make_live(project)

    plan = ProjectSetupPlan.for(project)
    expect(plan.items.map(&:key)).not_to include(:alerts)
    expect(Marshal.load(Marshal.dump(described_class.from_plan(plan))).state).to eq(described_class.from_plan(plan).state)
  end

  describe "caching" do
    let(:store) { ActiveSupport::Cache::MemoryStore.new }
    let(:project) { create(:project, :ruby) }

    before { allow(Rails).to receive(:cache).and_return(store) }

    it "reads evidence once and serves later requests from the shared cache" do
      described_class.for(project)
      queries = capture_sql { ProjectReadCache.set(values: {}) { described_class.for(project) } }

      expect(queries).to be_empty
    end

    it "shows a change straight away once the summary is expired" do
      expect(described_class.for(project).state).to eq(:incomplete)
      make_live(project)
      ProjectReadCache.set(values: {}) { expect(described_class.for(project).state).to eq(:incomplete) }

      described_class.expire(project)

      ProjectReadCache.set(values: {}) { expect(described_class.for(project).state).to eq(:live_with_steps) }
    end

    it "falls back to reading evidence when the cache is unavailable" do
      broken = instance_double(ActiveSupport::Cache::Store)
      allow(broken).to receive(:fetch).and_raise(Redis::CannotConnectError) if defined?(Redis::CannotConnectError)
      allow(broken).to receive(:fetch).and_raise(StandardError, "cache down") unless defined?(Redis::CannotConnectError)
      allow(Rails).to receive(:cache).and_return(broken)

      expect(described_class.for(project).state).to eq(:incomplete)
    end

    it "does not swallow an error from computing the summary" do
      allow(ProjectSetupPlan).to receive(:for).and_raise(ArgumentError, "boom")

      expect { described_class.for(project) }.to raise_error(ArgumentError, "boom")
    end
  end
end

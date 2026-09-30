# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectSetupPlan do
  let(:owner) { create(:user, name: "Olive Owner") }

  def plan_for(project, viewer: project.user)
    described_class.for(project, viewer: viewer)
  end

  def make_live(project)
    key = create(:api_key, project: project, user: project.user)
    create(:ingest_event, project: project, api_key: key)
  end

  describe "a new server project" do
    let(:project) { create(:project, :ruby, user: owner) }

    it "is not live and offers the API key as the first step" do
      plan = plan_for(project)

      expect(plan.live?).to be(false)
      expect(plan.next_item.key).to eq(:api_key)
      expect(plan.next_item.owner).to eq(:manager)
      expect(plan.next_item.action.label).to eq("Create API key")
      expect(plan.next_item.action.path).to eq("/projects/#{project.uuid}/setup/receive_data/api_key")
    end

    it "blocks the first event until the API key exists, and says why" do
      first_event = plan_for(project).item(:first_event)

      expect(first_event.state).to eq(:blocked)
      expect(first_event.blocker).to eq(:dependency)
      expect(first_event.evidence).to eq("Finish api key first.")
      expect(first_event.action).to be_nil
      expect(first_event.actionable?).to be(false)
    end

    it "counts required steps and only required steps toward going live" do
      plan = plan_for(project)

      expect(plan.required_total).to eq(2)
      expect(plan.required_done_count).to eq(0)
      expect(plan.groups.map(&:label)).to eq([ "Start receiving data", "Make issues actionable", "Bring in your team", "Extend coverage" ])
    end

    it "becomes live from evidence alone and then recommends a recommended step" do
      make_live(project)

      plan = plan_for(project)
      expect(plan.live?).to be(true)
      expect(plan.item(:api_key).state).to eq(:complete)
      expect(plan.item(:first_event).state).to eq(:complete)
      expect(plan.next_item.step.group.recommended?).to be(true)
    end

    it "never suggests an optional step as the next step" do
      make_live(project)
      plan = plan_for(project)

      expect(plan.next_item.step.group.optional?).to be(false)
      expect(plan.item(:linked_projects).step.group.optional?).to be(true)
    end
  end

  describe "who does each step" do
    let(:project) { create(:project, :ruby, user: owner) }

    it "gives a member who cannot manage the project an ask action that names the managers" do
      admin = create(:user, name: "Ada Admin")
      create(:project_membership, project: project, user: admin, role: :admin)
      viewer = create(:user)
      create(:project_membership, project: project, user: viewer, role: :viewer)

      api_key = plan_for(project, viewer: viewer).item(:api_key)

      expect(api_key.action.kind).to eq(:ask)
      expect(api_key.action.path).to be_nil
      expect(api_key.action.note).to include("Olive Owner", "Ada Admin")
    end

    it "gives no action to a non-manager once a manager-owned step is already done" do
      key = create(:api_key, project: project, user: owner)
      create(:ingest_event, project: project, api_key: key)
      viewer = create(:user)
      create(:project_membership, project: project, user: viewer, role: :viewer)

      expect(plan_for(project, viewer: viewer).item(:api_key).action).to be_nil
    end

    it "keeps steps done in the project's own code as guides for everyone" do
      make_live(project)
      viewer = create(:user)
      create(:project_membership, project: project, user: viewer, role: :viewer)

      deployments = plan_for(project, viewer: viewer).item(:deployments)
      expect(deployments.owner).to eq(:code)
      expect(deployments.owner_label).to eq("Your CI")
      expect(deployments.action.kind).to eq(:guide)
    end

    it "labels mobile steps with the place the work happens" do
      android = create(:project, :android, user: owner)
      plan = plan_for(android)

      expect(plan.item(:mobile_token).owner_label).to eq("Your backend")
      expect(plan.item(:first_diagnostic).owner_label).to eq("Your app code")
      expect(plan.item(:mapping).owner_label).to eq("Project manager")
    end
  end

  describe "skipping" do
    let(:project) { create(:project, :ruby, user: owner) }

    before { make_live(project) }

    it "marks an unobserved recommended or optional step as not needed" do
      project.setup_steps.create!(key: "linked_projects", decided_by_user: owner)
      project.setup_steps.create!(key: "source_repo", decided_by_user: owner)
      plan = plan_for(project)

      expect(plan.item(:linked_projects).state).to eq(:skipped)
      expect(plan.item(:linked_projects).done?).to be(true)
      expect(plan.item(:source_repo).state).to eq(:skipped)
      expect(plan.next_item&.key).not_to eq(:source_repo)
    end

    it "lets evidence outrank a skip once the work is actually done" do
      project.setup_steps.create!(key: "teammates", decided_by_user: owner)
      create(:project_membership, project: project, user: create(:user))

      expect(plan_for(project).item(:teammates).state).to eq(:complete)
    end

    it "honors a skip of a failing optional integration until evidence completes it" do
      android = create(:project, :android, user: owner)
      setting = create(:project_integration_setting, project: android, provider: "google_play", enabled: true,
                       external_project_id: "com.acme.shop", credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS",
                       last_imported_at: 2.days.ago,
                       metadata: { "last_error" => { "message" => "denied", "at" => Time.current.utc.iso8601 } })
      expect(plan_for(android).item(:google_play).state).to eq(:failed)

      android.setup_steps.create!(key: "google_play", decided_by_user: owner)
      plan = plan_for(android)
      expect(plan.item(:google_play).state).to eq(:skipped)
      expect(plan.attention_item).to be_nil

      setting.update!(metadata: {}, last_imported_at: Time.current)
      expect(plan_for(android).item(:google_play).state).to eq(:complete)
    end

    it "rejects skipping a required or personal step" do
      expect(project.setup_steps.build(key: "first_event")).not_to be_valid
      expect(project.setup_steps.build(key: "alerts")).not_to be_valid
      expect(project.setup_steps.build(key: "nonsense")).not_to be_valid
      expect(project.setup_steps.build(key: "teammates")).to be_valid
    end

    it "exposes skip and undo only for steps that can be skipped" do
      plan = plan_for(project)

      expect(plan.item(:linked_projects).skippable).to be(true)
      expect(plan.item(:first_event).skippable).to be(false)
      expect(plan.item(:alerts).skippable).to be(false)
    end
  end

  describe "instance prerequisites" do
    let(:project) { create(:project, :ruby, user: owner) }

    before { make_live(project) }

    it "blocks alerts and names the Logister admin when outbound email is not set up" do
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(false)

      alerts = plan_for(project).item(:alerts)

      expect(alerts.state).to eq(:blocked)
      expect(alerts.blocker).to eq(:instance)
      expect(alerts.owner).to eq(:instance_admin)
      expect(alerts.owner_label).to eq("Logister admin")
      expect(alerts.evidence).to include("Outbound email")
    end

    it "sends a project user to their admin, and gives an admin a direct link" do
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(false)

      user_action = plan_for(project).item(:alerts).action
      expect(user_action.kind).to eq(:ask)
      expect(user_action.path).to be_nil
      expect(user_action.copy_path).to eq("/admin/installation/email")

      admin = create(:user, application_admin: true)
      admin_action = plan_for(project, viewer: admin).item(:alerts).action
      expect(admin_action.kind).to eq(:admin)
      expect(admin_action.path).to eq("/admin/installation/email")
    end

    it "does not offer or count steps that are waiting on an instance setting" do
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(false)
      allow(Logister::GithubAppConfig).to receive(:configured?).and_return(false)

      plan = plan_for(project)

      expect(plan.item(:source_repo).blocker).to eq(:instance)
      expect(plan.next_item&.key).not_to be_in(%i[alerts source_repo])
      expect(plan.open_recommended_items.map(&:key)).not_to include(:alerts, :source_repo)
    end

    it "keeps evidence that already exists even when the instance service is later missing" do
      repo = create(:project_source_repository, project: project) if FactoryBot.factories.registered?(:project_source_repository)
      skip "no source repository factory" unless repo
      allow(Logister::GithubAppConfig).to receive(:configured?).and_return(false)

      expect(plan_for(project).item(:source_repo).state).to eq(:complete)
    end
  end

  describe "your alerts" do
    let(:project) { create(:project, :ruby, user: owner) }

    before do
      make_live(project)
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(true)
    end

    it "is complete by default because first-occurrence and regression alerts start on" do
      expect(plan_for(project).item(:alerts).state).to eq(:complete)
    end

    it "asks the person to review when every alert is off" do
      preference = ProjectNotificationPreference.for(user: owner, project: project)
      preference.unsubscribe_from_project_email!

      alerts = plan_for(project).item(:alerts)
      expect(alerts.state).to eq(:pending)
      expect(alerts.evidence).to eq("All alerts are off for you on this project.")
      expect(alerts.action.path).to eq("/projects/#{project.uuid}/setup/team/alerts")
    end

    it "is personal, so a viewer-less plan does not include it" do
      expect(plan_for(project, viewer: nil).item(:alerts)).to be_nil
      expect(plan_for(project).item(:alerts)).to be_present
    end
  end

  describe "archive exports" do
    it "only applies when the project's retention policy writes archives" do
      project = create(:project, :ruby)
      project.create_retention_policy!(archive_enabled: false) unless project.retention_policy

      project.retention_policy.update!(archive_enabled: false, archive_before_delete: false)
      expect(plan_for(project).item(:archive_exports)).to be_nil

      project.retention_policy.update!(archive_enabled: true)
      expect(plan_for(project).item(:archive_exports)).to be_present
    end
  end

  describe "mobile projects" do
    it "sequences required mobile steps and shows a failed store import as needing attention" do
      project = create(:project, :android)
      setting = create(
        :project_integration_setting, project: project, provider: "google_play", enabled: true,
        external_project_id: "com.acme.shop", credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS",
        last_imported_at: 2.days.ago
      )
      setting.update!(metadata: { "last_error" => { "message" => "denied", "at" => Time.current.utc.iso8601 } })

      plan = plan_for(project)

      expect(plan.item(:first_diagnostic).state).to eq(:blocked)
      expect(plan.item(:google_play).state).to eq(:failed)
      expect(plan.attention_item.key).to eq(:google_play)
      expect(plan.item(:google_play).action.label).to eq("Fix connection")
    end
  end

  describe "sections that depend on a step" do
    it "lists the steps that fill an empty section" do
      plan = plan_for(create(:project, :ruby))

      expect(plan.items_filling(:releases).map(&:key)).to eq([ :deployments ])
      expect(plan.items_filling(:performance).map(&:key)).to eq([ :performance ])
      expect(plan.items_filling(:monitors).map(&:key)).to eq([ :check_ins ])
    end
  end

  # Measured at 15 (server), 20 (Android) and 22 (iOS) queries. The ceilings leave
  # a little headroom but fail if the plan starts reading more per project.
  it "runs a bounded number of queries so it stays cheap to build" do
    { ruby: 18, android: 23, ios: 25 }.each do |kind, ceiling|
      project = create(:project, kind)
      queries = capture_sql { plan_for(project).items }

      expect(queries.size).to be <= ceiling, "#{kind} plan ran #{queries.size} queries"
    end
  end
end

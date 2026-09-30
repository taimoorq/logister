# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Setup prompts in empty sections", type: :request do
  let(:owner) { users(:one) }
  let(:project) { create(:project, :ruby, user: owner) }

  def prompt(key = nil)
    selector = key ? "[data-setup-prompt='#{key}']" : "[data-setup-prompt]"
    Nokogiri::HTML.parse(response.body).at_css(selector)
  end

  def make_live(target = project)
    api_key = create(:api_key, project: target, user: target.user)
    create(:ingest_event, project: target, api_key: api_key)
    api_key
  end

  before { sign_in owner }

  describe "Overview" do
    it "asks for the API key first, then the first event, then goes away" do
      get project_path(project)
      expect(prompt("api_key")).to be_present
      expect(prompt("api_key").text).to include("Setup · Start receiving data", "Create API key")

      create(:api_key, project: project, user: owner)
      get project_path(project)
      expect(prompt("first_event")).to be_present
      expect(prompt("first_event").text).to include("Done in your code or CI")

      make_live
      get project_path(project)
      expect(prompt).to be_nil
    end
  end

  describe "Issues" do
    it "points an empty project at the step that will fill it" do
      get inbox_project_path(project)

      expect(prompt("api_key")).to be_present
      expect(prompt("api_key").at_css("a.btn-primary")["href"]).to eq(setup_step_project_path(project, group: "receive_data", step: "api_key"))
    end

    it "names the first diagnostic for a mobile project once its token exists" do
      android = create(:project, :android, user: owner)
      create(:mobile_ingest_token, project: android) if FactoryBot.factories.registered?(:mobile_ingest_token)

      get inbox_project_path(android)

      expect(prompt).to be_present
      expect(prompt.text).to include("Setup · Start receiving data")
    end

    it "does not appear once an issue exists" do
      api_key = make_live
      event = create(:ingest_event, project: project, api_key: api_key, event_type: :error, level: "error")
      ErrorGroupingService.call(event)

      get inbox_project_path(project)

      expect(prompt).to be_nil
    end
  end

  describe "Explore › Events" do
    it "adds the next step above the tailored guidance for the integration" do
      get activity_project_path(project)

      expect(prompt("api_key")).to be_present
      expect(response.body).to include("No events yet.", "logister-ruby")
      expect(response.body.index("data-setup-prompt")).to be < response.body.index("No events yet.")
    end

    it "stays out of the way when filters are applied" do
      get activity_project_path(project, event_type: "log")

      expect(prompt).to be_nil
      expect(response.body).to include("No events match these filters.")
    end

    it "stays out of the way when events exist" do
      make_live

      get activity_project_path(project)

      expect(prompt).to be_nil
    end
  end

  describe "Performance" do
    it "asks for instrumentation until a transaction arrives" do
      make_live

      get performance_project_path(project)
      expect(prompt("performance")).to be_present
      expect(prompt("performance").text).to include("Performance instrumentation", "Done in your code or CI")

      create(:ingest_event, :transaction, project: project, api_key: project.api_keys.first, occurred_at: 1.hour.ago)
      get performance_project_path(project)
      expect(prompt).to be_nil
    end

    it "does not add a prompt to the mobile app health view" do
      get performance_project_path(create(:project, :android, user: owner))

      expect(prompt("performance")).to be_nil
    end
  end

  describe "Releases" do
    it "asks CI to record deployments when a server project has none" do
      make_live

      get deployments_project_path(project)

      expect(prompt("deployments")).to be_present
      expect(prompt("deployments").text).to include("Your CI")
    end

    it "keeps the filter message when filters hide every deployment" do
      make_live
      create(:project_deployment, project: project)

      get deployments_project_path(project, repository: "nonexistent/repo")

      expect(prompt).to be_nil
      expect(response.body).to include("No deployments match these filters.")
    end

    it "does not appear once a deployment is recorded" do
      make_live
      create(:project_deployment, project: project)

      get deployments_project_path(project)

      expect(prompt).to be_nil
    end

    it "keeps its plain message on a mobile project, where deploy records are optional" do
      get deployments_project_path(create(:project, :ios, user: owner))

      expect(prompt).to be_nil
      expect(response.body).to include("No deployments have been recorded yet.")
    end

    it "points an empty mobile project at the step it is really waiting on" do
      get releases_project_path(create(:project, :android, user: owner))

      expect(prompt("mobile_token")).to be_present
      expect(prompt("mobile_token").text).to include("Mobile token", "Your backend")
    end
  end

  describe "Monitors" do
    it "asks for a first check-in when none has been received" do
      make_live

      get monitors_project_path(project)

      expect(prompt("check_ins")).to be_present
      expect(response.body).not_to include("No check-ins yet.")
    end

    it "shows the monitors themselves once one exists" do
      make_live
      create(:check_in_monitor, project: project)

      get monitors_project_path(project)

      expect(prompt).to be_nil
    end
  end

  describe "Settings › Notifications" do
    before { make_live }

    it "tells the person their alerts cannot be delivered yet, and who can fix it" do
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(false)

      get settings_project_path(project, section: "notifications")

      expect(prompt("alerts")).to be_present
      expect(prompt("alerts").text).to include("Outbound email", "Logister admin")
      expect(prompt("alerts").at_css("[data-controller='copy']")["data-copy-text-value"]).to end_with("/admin/installation/email")
    end

    it "stays quiet when email works and alerts are on" do
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(true)

      get settings_project_path(project, section: "notifications")

      expect(prompt).to be_nil
    end

    it "asks the person to review when every alert is off" do
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(true)
      ProjectNotificationPreference.for(user: owner, project: project).unsubscribe_from_project_email!

      get settings_project_path(project, section: "notifications")

      expect(prompt("alerts")).to be_present
      expect(prompt("alerts").text).to include("All alerts are off for you")
    end
  end

  describe "who is asked" do
    it "tells a member who cannot manage the project to ask a manager" do
      viewer = create(:user)
      create(:project_membership, project: project, user: viewer, role: :viewer)
      sign_out owner
      sign_in viewer

      get project_path(project)

      expect(prompt("api_key")).to be_present
      expect(prompt("api_key").text).to include("Ask")
      expect(prompt("api_key").at_css("a.btn-primary")).to be_nil
    end
  end

  it "adds no more than a handful of queries to the page it appears on" do
    make_live
    get performance_project_path(project) # warm any per-process state
    with_prompt = capture_sql { get performance_project_path(project) }
    create(:ingest_event, :transaction, project: project, api_key: project.api_keys.first, occurred_at: 1.hour.ago)
    without_prompt = capture_sql { get performance_project_path(project) }

    expect(with_prompt.size - without_prompt.size).to be <= 8
  end
end

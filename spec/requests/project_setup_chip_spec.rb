# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Project setup chip", type: :request do
  let(:owner) { users(:one) }
  let(:project) { create(:project, :ruby, user: owner) }
  let(:frame_headers) { { "Turbo-Frame" => "setup_chip" } }

  def chip
    Nokogiri::HTML.parse(response.body).at_css("[data-setup-chip]")
  end

  def chip_frame
    Nokogiri::HTML.parse(response.body).at_css("turbo-frame#setup_chip")
  end

  before { sign_in owner }

  describe "the frame in the project header" do
    it "is a lazy frame that never reads setup evidence while rendering the page" do
      get performance_project_path(project)

      frame = Nokogiri::HTML.parse(response.body).at_css("turbo-frame#setup_chip")
      expect(frame["src"]).to eq(setup_chip_project_path(project))
      expect(frame.at_css(".setup-chip-loading")).to be_present
      expect(frame.at_css("noscript")).to be_present
    end

    it "appears on every project page for a member" do
      [ project_path(project), inbox_project_path(project), activity_project_path(project), monitors_project_path(project), settings_project_path(project) ].each do |path|
        get path
        expect(chip_frame).to be_present, "#{path} has no setup chip frame"
      end
    end

    it "is left out for archived projects" do
      archived = create(:project, :archived, user: owner)

      get settings_project_path(archived)

      expect(chip_frame).to be_nil
    end

    it "is left out for an application admin who is only managing settings" do
      admin = create(:user, application_admin: true)
      sign_out owner
      sign_in admin

      get settings_project_path(project)

      expect(response).to have_http_status(:success)
      expect(chip_frame).to be_nil
    end
  end

  describe "GET /projects/:uuid/setup_chip" do
    it "names the next thing to do while the project is not live" do
      get setup_chip_project_path(project), headers: frame_headers

      expect(response).to have_http_status(:success)
      expect(chip_frame).to be_present
      expect(chip["data-setup-chip"]).to eq("incomplete")
      expect(chip.text).to include("Create an API key", "Continue setup")
      expect(chip.at_css("a")["href"]).to eq(setup_project_path(project, anchor: "step-api_key"))
      expect(chip.at_css("a")["data-turbo-frame"]).to eq("_top")
    end

    it "moves on to waiting for the first event once a key exists" do
      create(:api_key, project: project, user: owner)

      get setup_chip_project_path(project), headers: frame_headers

      expect(chip.text).to include("Waiting for first event")
    end

    it "counts remaining recommended steps once the project is live" do
      key = create(:api_key, project: project, user: owner)
      create(:ingest_event, project: project, api_key: key)

      get setup_chip_project_path(project), headers: frame_headers

      expect(chip["data-setup-chip"]).to eq("live_with_steps")
      expect(chip.text).to match(/Live\s+\d+ setup steps?/)
      expect(chip.at_css("a")["href"]).to eq(setup_project_path(project))
    end

    it "goes quiet, with no link, when nothing is left" do
      key = create(:api_key, project: project, user: owner)
      create(:ingest_event, project: project, api_key: key)
      allow(Logister::GithubAppConfig).to receive(:configured?).and_return(true)
      ProjectSetupCatalog.steps_for(:server).reject { |step| step.group.required? || step.personal }.each do |step|
        project.setup_steps.create!(key: step.key.to_s, decided_by_user: owner)
      end

      get setup_chip_project_path(project), headers: frame_headers

      expect(chip["data-setup-chip"]).to eq("live")
      expect(chip.at_css("a")).to be_nil
    end

    it "raises a failing integration above everything else" do
      android = create(:project, :android, user: owner)
      setting = create(
        :project_integration_setting, project: android, provider: "google_play", enabled: true,
        external_project_id: "com.acme.shop", credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS",
        last_imported_at: 2.days.ago
      )
      setting.update!(metadata: { "last_error" => { "message" => "denied", "at" => Time.current.utc.iso8601 } })

      get setup_chip_project_path(android), headers: frame_headers

      expect(chip["data-setup-chip"]).to eq("attention")
      expect(chip.text).to include("Google Play failed", "Fix")
    end

    it "describes every state with words as well as color" do
      get setup_chip_project_path(project), headers: frame_headers

      expect(chip.text.strip).not_to be_empty
      expect(chip.at_css("[aria-hidden='true']")).to be_present
    end

    it "sends a direct visit to the Setup page instead of a bare fragment" do
      get setup_chip_project_path(project)

      expect(response).to redirect_to(setup_project_path(project))
    end

    it "returns nothing for an archived project" do
      archived = create(:project, :archived, user: owner)

      get setup_chip_project_path(archived), headers: frame_headers

      expect(response).to have_http_status(:no_content)
    end
  end
end

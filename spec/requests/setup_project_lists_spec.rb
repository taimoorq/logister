# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Setup cues on project lists", type: :request do
  let(:owner) { create(:user) }

  def document
    Nokogiri::HTML.parse(response.body)
  end

  def receive_event(project)
    key = create(:api_key, project: project, user: owner)
    create(:ingest_event, project: project, api_key: key)
  end

  before { sign_in owner }

  describe "GET /projects" do
    it "flags active projects that have never received data and links to their setup" do
      waiting = create(:project, :ruby, user: owner, name: "Waiting Project")

      get projects_path

      cue = document.at_css("article[data-project-name='waiting project'] [data-project-setup-cue]")
      expect(cue).to be_present
      expect(cue["href"]).to eq(setup_project_path(waiting))
      expect(cue.text).to include("Setup needed")
    end

    it "does not flag a project that is already receiving data" do
      receiving = create(:project, :ruby, user: owner, name: "Receiving Project")
      receive_event(receiving)

      get projects_path

      expect(document.at_css("article[data-project-name='receiving project'] [data-project-setup-cue]")).to be_nil
    end

    it "does not flag archived projects" do
      create(:project, :archived, user: owner, name: "Archived Project")

      get projects_path(filter: "archived")

      expect(document.at_css("[data-project-setup-cue]")).to be_nil
    end
  end

  describe "GET /dashboard" do
    it "lists projects waiting for data with a way to continue setup" do
      waiting = create(:project, :android, user: owner, name: "Waiting App")

      get dashboard_path

      panel = document.at_css("[data-dashboard-setup]")
      expect(panel).to be_present
      expect(panel.text).to include("Finish setting up", "Waiting App", "1 project waiting for data")
      expect(panel.at_css("a[href='#{setup_project_path(waiting)}']").text).to eq("Continue setup")
    end

    it "disappears once every project is receiving data" do
      receive_event(create(:project, :ruby, user: owner))

      get dashboard_path

      expect(document.at_css("[data-dashboard-setup]")).to be_nil
    end

    it "shows at most five projects" do
      create_list(:project, 7, :ruby, user: owner)

      get dashboard_path

      expect(document.css("[data-dashboard-setup] li").size).to eq(5)
    end

    it "never lists another person's projects" do
      create(:project, :ruby, name: "Someone Elses Project")

      get dashboard_path

      expect(document.at_css("[data-dashboard-setup]")).to be_nil
      expect(response.body).not_to include("Someone Elses Project")
    end

    it "costs one extra indexed query on the overview tab" do
      create_list(:project, 3, :ruby, user: owner)
      get dashboard_path
      with_panel = capture_sql { get dashboard_path }

      receive_event(Project.where(user: owner).first)
      Project.where(user: owner).find_each { |project| receive_event(project) unless project.ingest_events.exists? }
      without_panel = capture_sql { get dashboard_path }

      expect(with_panel.size - without_panel.size).to be_between(-1, 1)
      expect(with_panel.grep(/latest_events/).size).to eq(1)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Project setup hub", type: :request do
  let(:owner) { users(:one) }
  let(:project) { create(:project, :ruby, user: owner, name: "Hub Project") }

  def document
    Nokogiri::HTML.parse(response.body)
  end

  def item(key)
    document.at_css("#step-#{key}")
  end

  describe "GET /projects/:uuid/setup" do
    before { sign_in owner }

    it "shows the next step, four outcome groups, and who does each step" do
      get setup_project_path(project)

      expect(response).to have_http_status(:success)
      expect(document.at_css("#setup-next-title").text).to eq("API key")
      expect(document.css(".setup-group-title").map { |node| node.text.strip }).to eq([
        "1 · Start receiving data", "2 · Make issues actionable", "3 · Bring in your team", "4 · Extend coverage"
      ])
      expect(item(:api_key)["data-setup-owner"]).to eq("manager")
      expect(item(:first_event)["data-setup-state"]).to eq("blocked")
      expect(item(:first_event).text).to include("Finish api key first.")
      expect(document.at_css(".setup-legend").text).to include("Who does each step", "Logister admin")
    end

    it "keeps credentials on the hub and sends each step's button to its page in the setup path" do
      get setup_project_path(project)

      expect(document.at_css("#api-keys")).to be_present
      expect(item(:api_key).at_css("a")["href"]).to eq(setup_step_project_path(project, group: "receive_data", step: "api_key"))
      expect(item(:deployments).at_css("a")["href"]).to eq(setup_step_project_path(project, group: "actionable", step: "deployments"))
    end

    it "describes progress by requirement and marks the project live once required steps are done" do
      key = create(:api_key, project: project, user: owner)
      create(:ingest_event, project: project, api_key: key)

      get setup_project_path(project)

      counts = document.css(".setup-hub-counts li").map { |node| node.text.squish }
      expect(counts.first).to eq("Required 2/2")
      expect(document.at_css("#group-receive_data")).to be_present
      expect(document.at_css("#group-receive_data").name).to eq("details")
      expect(document.at_css("#group-receive_data summary").text).to include("Complete")
    end

    it "gives every step a non-color state cue and a readable state name" do
      get setup_project_path(project)

      document.css(".setup-item").each do |row|
        expect(row.at_css(".setup-marker .sr-only").text).to be_present
      end
    end

    it "shows a blocked step as waiting on the Logister admin with a copyable link" do
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(false)

      get setup_project_path(project)

      alerts = item(:alerts)
      expect(alerts["data-setup-state"]).to eq("blocked")
      expect(alerts["data-setup-owner"]).to eq("instance_admin")
      expect(alerts.text).to include("Outbound email", "Logister admin", "Copy link for admin")
      expect(alerts.at_css("[data-controller='copy']")["data-copy-text-value"]).to end_with("/admin/installation/email")
    end

    it "lets a member who is not a manager see setup without manager actions" do
      viewer = create(:user, name: "View Only")
      create(:project_membership, project: project, user: viewer, role: :viewer)
      sign_out owner
      sign_in viewer

      get setup_project_path(project)

      expect(response).to have_http_status(:success)
      expect(item(:api_key).text).to include("Ask", owner.name.presence || owner.email)
      expect(document.css("form[action*='setup_skips']")).to be_empty
    end

    it "offers Not needed only on unobserved optional steps and Undo once skipped" do
      get setup_project_path(project)
      expect(item(:linked_projects).at_css("form[action='#{project_setup_skips_path(project, key: 'linked_projects')}']")).to be_present
      expect(item(:first_event).at_css("form")).to be_nil

      project.setup_steps.create!(key: "linked_projects", decided_by_user: owner)
      get setup_project_path(project)
      expect(item(:linked_projects)["data-setup-state"]).to eq("skipped")
      expect(item(:linked_projects).at_css("form[action='#{project_setup_skip_path(project, 'linked_projects')}'] input[value='delete']")).to be_present
    end

    it "lets a manager dismiss an optional step that is stuck waiting on the instance" do
      allow(ProjectCorrelationPolicy).to receive(:instance_enabled?).and_return(false)

      get setup_project_path(project)

      expect(item(:linked_projects)["data-setup-state"]).to eq("blocked")
      expect(item(:linked_projects).at_css("form[action*='setup_skips']")).to be_present

      post project_setup_skips_path(project), params: { key: "linked_projects" }
      get setup_project_path(project)
      expect(item(:linked_projects)["data-setup-state"]).to eq("skipped")
    end

    it "renders mobile setup with the shared groups and mobile steps" do
      android = create(:project, :android, user: owner)

      get setup_project_path(android)

      expect(document.css(".setup-group-title").map { |node| node.text.strip }.first).to eq("1 · Start receiving data")
      expect(item(:mobile_token)["data-setup-owner"]).to eq("code")
      expect(item(:mapping)).to be_present
      expect(item(:api_key)).to be_nil
    end
  end

  describe "skipping a step" do
    before { sign_in owner }

    it "records the decision and returns to that step" do
      expect {
        post project_setup_skips_path(project), params: { key: "linked_projects" }
      }.to change { project.setup_steps.count }.by(1)

      expect(response).to redirect_to(setup_project_path(project, anchor: "step-linked_projects"))
      expect(project.setup_steps.find_by!(key: "linked_projects").decided_by_user).to eq(owner)
      follow_redirect!
      expect(response.body).to include("marked as not needed")
    end

    it "is idempotent" do
      post project_setup_skips_path(project), params: { key: "linked_projects" }
      expect { post project_setup_skips_path(project), params: { key: "linked_projects" } }
        .not_to change { project.setup_steps.count }
    end

    it "refuses required, personal, and unknown steps" do
      %w[first_event api_key alerts nonsense].each do |key|
        expect { post project_setup_skips_path(project), params: { key: key } }
          .not_to change { project.setup_steps.count }

        expect(response).to redirect_to(setup_project_path(project))
        expect(flash[:alert]).to be_present
      end
    end

    it "undoes a skip" do
      project.setup_steps.create!(key: "linked_projects", decided_by_user: owner)

      expect { delete project_setup_skip_path(project, "linked_projects") }
        .to change { project.setup_steps.count }.by(-1)

      expect(response).to redirect_to(setup_project_path(project, anchor: "step-linked_projects"))
    end

    it "only lets a project manager decide" do
      viewer = create(:user)
      create(:project_membership, project: project, user: viewer, role: :viewer)
      sign_out owner
      sign_in viewer

      expect { post project_setup_skips_path(project), params: { key: "linked_projects" } }
        .not_to change { project.setup_steps.count }
      expect(response).to have_http_status(:not_found)
    end

    it "does not touch another person's project" do
      stranger_project = create(:project, :ruby)

      expect { post project_setup_skips_path(stranger_project), params: { key: "linked_projects" } }
        .not_to change { ProjectSetupStep.count }
      expect(response).to have_http_status(:not_found)
    end
  end
end

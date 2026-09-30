# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Creating a project in guided steps", type: :request do
  let(:user) { users(:one) }
  let(:retention) do
    { hot_retention_days: "60", trace_retention_days: "90", error_retention_days: "180", archive_enabled: "1", archive_before_delete: "1" }
  end

  def document
    Nokogiri::HTML.parse(response.body)
  end

  before { sign_in user }

  it "starts the guided steps from the usual new-project link" do
    get new_project_path

    expect(response).to redirect_to(new_project_step_path("platform"))
  end

  it "keeps the one-page form as a quick path" do
    get new_project_quick_path

    expect(response).to have_http_status(:success)
    expect(document.at_css("form[action='#{projects_path}'] input[name='project[name]']")).to be_present
    expect(document.at_css("header.wz-bar")).to be_nil
  end

  describe "the wizard layout" do
    it "uses the focused layout, with a way out that leaves nothing behind" do
      get new_project_step_path("platform")

      expect(response).to have_http_status(:success)
      expect(document.at_css("nav[aria-label='Project sections']")).to be_nil
      bar = document.at_css("header.wz-bar")
      expect(bar.text).to include("New project", "Create: Platform")
      expect(bar.at_css("a").text).to eq("Cancel")
      expect(bar.at_css("a")["href"]).to eq(projects_path)
      expect(document.at_css("[role='progressbar']")["aria-valuetext"]).to eq("0 of 4 steps done")
    end

    it "lists every step, marks the current one, and shows that setup continues afterwards" do
      get new_project_step_path("platform")

      rail = document.at_css("nav[aria-label='Steps to create a project']")
      expect(rail.css("li").map { |li| li.text.squish }).to eq([
        "1 Platform What sends telemetry",
        "2 Name and description How your team finds it",
        "3 Data retention How long to keep events",
        "4 Connect Continues as the project's setup path"
      ])
      expect(rail.at_css("li[aria-current='step']").text).to include("Platform")
      expect(document.css("h1").size).to eq(1)
    end

    it "has no page for an unknown step" do
      get "/projects/new/nonsense"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "step 1: platform" do
    it "offers every integration with Ruby chosen, and moves on with a GET so the choice lives in the URL" do
      get new_project_step_path("platform")

      form = document.at_css("form[action='#{new_project_step_path('details')}']")
      expect(form["method"]).to eq("get")
      expect(form.css("input[type='radio'][name='project[integration_kind]']").size).to eq(9)
      expect(form.at_css("input[type='radio'][checked]")["value"]).to eq("ruby")
      expect(form.at_css("button[type='submit']").text).to eq("Continue: Name and description")
      expect(document.at_css("a[href='#{new_project_quick_path}']").text).to include("quick form")
    end

    it "keeps an earlier choice when someone comes back" do
      get new_project_step_path("platform", project: { integration_kind: "python", name: "Kept Name" })

      expect(document.at_css("input[type='radio'][checked]")["value"]).to eq("python")
      expect(document.at_css("input[type='hidden'][name='project[name]']")["value"]).to eq("Kept Name")
    end

    it "ignores an integration that does not exist" do
      get new_project_step_path("platform", project: { integration_kind: "cobol" })

      expect(document.at_css("input[type='radio'][checked]")["value"]).to eq("ruby")
    end
  end

  describe "step 2: name and description" do
    it "asks for a platform first when none was chosen" do
      get new_project_step_path("details")

      expect(response).to redirect_to(new_project_step_path("platform"))
      expect(flash[:alert]).to include("what you are monitoring")
    end

    it "asks for the name, carries the platform forward, and shows the real setup path it leads to" do
      get new_project_step_path("details", project: { integration_kind: "ruby" })

      form = document.at_css("form[action='#{new_project_step_path('retention')}']")
      expect(form["method"]).to eq("get")
      expect(form.at_css("input[name='project[name]'][required]")).to be_present
      expect(form.at_css("label[for='project_name']")).to be_present
      expect(form.at_css("input[type='hidden'][name='project[integration_kind]']")["value"]).to eq("ruby")
      preview = document.at_css("aside[aria-labelledby='creation-preview-title']")
      expect(preview.text).to include("Ruby gem setup path", "API key", "First event")
    end

    it "shows the mobile path for a mobile platform" do
      get new_project_step_path("details", project: { integration_kind: "android" })

      preview = document.at_css("aside[aria-labelledby='creation-preview-title']")
      expect(preview.text).to include("Android app setup path", "Mobile token", "First diagnostic", "Your backend")
      expect(preview.text).not_to include("API key")
    end

    it "offers self-monitoring only to application admins on a Ruby project" do
      get new_project_step_path("details", project: { integration_kind: "ruby" })
      expect(document.at_css("input[name='project[monitor_this_installation]'][type='checkbox']")).to be_nil

      user.reload.update!(application_admin: true)
      get new_project_step_path("details", project: { integration_kind: "ruby" })
      expect(document.at_css("input[name='project[monitor_this_installation]'][type='checkbox']")).to be_present

      get new_project_step_path("details", project: { integration_kind: "python" })
      expect(document.at_css("input[name='project[monitor_this_installation]'][type='checkbox']")).to be_nil
    end

    it "lets someone go back with their choices intact" do
      get new_project_step_path("details", project: { integration_kind: "python", name: "Billing", description: "Invoices" })

      back = document.at_css("footer a").tap { |link| expect(link.text).to eq("Back") }
      expect(Rack::Utils.parse_nested_query(URI(back["href"]).query)).to include("project" => hash_including("integration_kind" => "python", "name" => "Billing"))
      expect(document.at_css("input[name='project[name]']")["value"]).to eq("Billing")
    end
  end

  describe "step 3: data retention" do
    it "asks for a name first when there is none" do
      get new_project_step_path("retention", project: { integration_kind: "ruby" })

      expect(response).to redirect_to(new_project_step_path("details", project: { integration_kind: "ruby" }))
      expect(flash[:alert]).to include("Name the project")
    end

    it "posts the whole project to the one create command, carrying the earlier steps forward" do
      get new_project_step_path("retention", project: { integration_kind: "python", name: "Billing", description: "Invoices" })

      form = document.at_css("form[action='#{projects_path}']")
      expect(form["method"]).to eq("post")
      expect(form.at_css("input[name='wizard'][value='1']")).to be_present
      expect(form.at_css("input[type='hidden'][name='project[name]']")["value"]).to eq("Billing")
      expect(form.at_css("input[type='hidden'][name='project[integration_kind]']")["value"]).to eq("python")
      expect(form.at_css("select[name='project[retention_policy_attributes][hot_retention_days]']")).to be_present
      expect(form.at_css("input[name='project[retention_policy_attributes][archive_enabled]'][type='checkbox']")).to be_present
      expect(form.at_css("button[type='submit']").text).to include("Create project")
    end

    it "keeps retention choices when someone goes back and returns" do
      get new_project_step_path("details", project: { integration_kind: "ruby", name: "Kept", retention_policy_attributes: { hot_retention_days: "30" } })

      expect(document.at_css("input[type='hidden'][name='project[retention_policy_attributes][hot_retention_days]']")["value"]).to eq("30")
    end
  end

  describe "creating the project" do
    def create_from_wizard(overrides = {})
      post projects_path, params: {
        wizard: "1",
        project: { name: "Guided App", description: "Made in steps", integration_kind: "ruby", retention_policy_attributes: retention }.merge(overrides)
      }
    end

    it "uses the same command as the quick form, and lands on the first step of the project's setup path" do
      expect { create_from_wizard }.to change(Project, :count).by(1).and change(ProjectRetentionPolicy, :count).by(1)

      project = Project.find_by!(name: "Guided App")
      expect(project.integration_kind).to eq("ruby")
      expect(response).to redirect_to(setup_step_project_path(project, group: "receive_data", step: "api_key"))
      follow_redirect!
      expect(document.at_css("header.wz-bar").text).to include("Guided App", "Setup: Start receiving data")
    end

    it "lands a mobile project on its mobile step" do
      create_from_wizard(integration_kind: "android")

      project = Project.find_by!(name: "Guided App")
      expect(response).to redirect_to(setup_step_project_path(project, group: "receive_data", step: "mobile_token"))
    end

    it "returns a missing name to the name step, with the choices already made" do
      expect { create_from_wizard(name: "") }.not_to change(Project, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(document.at_css("header.wz-bar").text).to include("Create: Name and description")
      expect(document.at_css("[role='alert']").text).to include("Name")
      expect(document.at_css("input[type='hidden'][name='project[integration_kind]']")["value"]).to eq("ruby")
      expect(document.at_css("textarea[name='project[description]']").text.strip).to eq("Made in steps")
    end

    it "returns a missing retention policy to the retention step" do
      post projects_path, params: { wizard: "1", project: { name: "No Policy", integration_kind: "ruby" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(document.at_css("header.wz-bar").text).to include("Create: Data retention")
      expect(document.at_css("[role='alert']").text).to include("retention policy")
    end

    it "returns a forged self-monitoring choice to the name step" do
      expect {
        post projects_path, params: { wizard: "1", project: { name: "Forged", integration_kind: "ruby", monitor_this_installation: "1", retention_policy_attributes: retention } }
      }.not_to change(Project, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(document.at_css("header.wz-bar").text).to include("Create: Name and description")
      expect(document.at_css("[role='alert']").text).to include("Application admin access is required")
    end

    it "still answers the quick form with the one-page form on failure" do
      post projects_path, params: { project: { name: "", integration_kind: "ruby", retention_policy_attributes: retention } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(document.at_css("header.wz-bar")).to be_nil
      expect(document.at_css("form[action='#{projects_path}'] input[name='project[name]']")).to be_present
    end
  end

  describe "the steps carry state through the URL, not a draft" do
    it "does not store anything until the project is created" do
      expect {
        get new_project_step_path("platform", project: { integration_kind: "ruby" })
        get new_project_step_path("details", project: { integration_kind: "ruby", name: "Draft" })
        get new_project_step_path("retention", project: { integration_kind: "ruby", name: "Draft" })
      }.not_to change { [ Project.count, ProjectRetentionPolicy.count ] }
    end
  end
end

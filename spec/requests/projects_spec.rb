# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Projects", type: :request do
  include ActiveJob::TestHelper

  describe "GET /projects" do
    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "returns success and lists projects" do
        get projects_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
        expect(response.body).to include("Ruby gem")
        expect(response.body).to include("Active apps")
        expect(response.body).to include("Receipts 7d", "Activity 7d")
        expect(response.body).to include("Active", "Archived", "All")
        expect(response.body).to include(">Docs<")
        expect(response.body).to include("Open the docs")
        expect(response.body).to include("https://logister.org/docs/")
        expect(response.body).to include('target="_blank"')
        expect(response.body).to include('rel="noopener noreferrer"')
      end

      it "renders Bugsnag-style project cards with clickable headers and counts" do
        project = create(:project, :dotnet, user: users(:one), name: "quria-work")
        api_key = create(:api_key, project: project, user: users(:one))
        create(:ingest_event, :transaction, project: project, api_key: api_key)
        create(:ingest_event, :log, project: project, api_key: api_key)

        get projects_path

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        card = document.css(".project-card").find { |node| node.text.include?("quria-work") }

        expect(card).to be_present
        expect(card.at_css(".project-card-header")["href"]).to eq(project_path(project))
        expect(card.at_css(".project-type-icon-dotnet use")["href"]).to match(%r{streamline-freehand(?:-[a-f0-9]+)?\.svg#streamline-project-dotnet\z})
        expect(card.at_css(".project-card-health")).to be_nil
        expect(card.text).not_to include("Session stability", "User stability", "Performance score")

        open_errors_link = card.at_css("a[href='#{inbox_project_path(project, filter: 'unresolved')}']")
        all_errors_link = card.at_css("a[href='#{inbox_project_path(project, filter: 'all')}']")
        activity_link = card.at_css("a[href='#{activity_project_path(project)}']")

        expect(open_errors_link).to be_present
        expect(open_errors_link.text).to include("Errors for review", "0", "No open errors")
        expect(all_errors_link).to be_present
        expect(all_errors_link.text).to include("All error groups", "0", "No errors yet")
        expect(activity_link).to be_present
        expect(activity_link.text).to include("Activity 7d", "2", "View activity")
        expect(card.at_css(".project-card-line-chart")).to be_present
        expect(card.text).to include("No open errors")
      end

      it "hides archived projects from the default list and shows them from the archived filter" do
        archived_project = create(:project, :archived, user: users(:one), name: "Resting App")
        create(:error_group, project: archived_project)

        get projects_path

        expect(response.body).not_to include("Resting App")

        get projects_path(filter: "archived")

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Resting App", "Archived apps")

        document = Nokogiri::HTML.parse(response.body)
        card = document.css(".project-card.is-archived").find { |node| node.text.include?(archived_project.name) }

        expect(card).to be_present
        expect(card.text).to include("Archived")
        expect(document.at_css(".projects-overview-strip a[href='#{dashboard_path}']")).to be_nil
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "includes shared project in list" do
        get projects_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(projects(:one).name)
      end
    end
  end

  describe "GET /projects/:uuid/edit" do
    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "sends old links to Settings › General, where the project is edited" do
        get edit_project_path(projects(:one))

        expect(response).to have_http_status(:moved_permanently)
        expect(response).to redirect_to(settings_project_path(projects(:one), section: "general"))
      end

      it "edits the name and description in General, and keeps the project type locked" do
        get settings_project_path(projects(:one), section: "general")
        expect(response).to have_http_status(:success)
        document = Nokogiri::HTML.parse(response.body)

        form = document.at_css("form[action='#{project_path(projects(:one))}']")
        expect(form.at_css("input[name='project[name]']")["value"]).to eq(projects(:one).name)
        expect(form.at_css("textarea[name='project[description]']")).to be_present
        expect(form.at_css("button").text).to include("Update project")
        expect(document.at_css("input[name='project[slug]']")).to be_nil
        expect(document.at_css("select[name='project[integration_kind]']")).to be_nil
        expect(document.at_css("input[name='project[integration_kind]']")).to be_nil
        expect(response.body).to include("Project type is locked after creation", projects(:one).integration_label)
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns 404 (only owner can edit)" do
        get edit_project_path(projects(:one))
        expect(response).to have_http_status(:not_found)
      end

      it "shows the project details read-only in General" do
        get settings_project_path(projects(:one), section: "general")

        document = Nokogiri::HTML.parse(response.body)
        expect(document.at_css("form[action='#{project_path(projects(:one))}']")).to be_nil
        expect(response.body).to include(projects(:one).name, "Project type is locked after creation")
      end
    end
  end

  describe "PATCH /projects/:uuid" do
    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "updates project and redirects to settings" do
        project = projects(:one)
        original_slug = project.slug

        patch project_path(project), params: { project: { name: "Renamed App", slug: "manual-change", description: "New desc", integration_kind: "http_api" } }

        expect(response).to redirect_to(settings_project_path(project, section: "general"))
        expect(project.reload.name).to eq("Renamed App")
        expect(project.slug).to eq(original_slug)
        expect(project.description).to eq("New desc")
        expect(project.integration_kind).to eq("ruby")
      end

      it "re-renders General with the error and what was entered when invalid" do
        patch project_path(projects(:one)), params: { project: { name: "", description: "Kept description" } }

        expect(response).to have_http_status(:unprocessable_content)
        document = Nokogiri::HTML.parse(response.body)
        expect(document.at_css("[role='alert']").text).to include("Name")
        expect(document.at_css("textarea[name='project[description]']").text.strip).to eq("Kept description")
        expect(document.at_css("nav[aria-label='Project settings sections'] a[aria-current='page']").text.strip).to eq("General")
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns 404 (only owner can update)" do
        patch project_path(projects(:one)), params: { project: { name: "Nope" } }
        expect(response).to have_http_status(:not_found)
        expect(projects(:one).reload.name).not_to eq("Nope")
      end
    end
  end

  describe "POST /projects" do
    before { sign_in users(:one) }

    let(:retention_policy_attributes) do
      {
        hot_retention_days: "60",
        trace_retention_days: "90",
        error_retention_days: "180",
        archive_enabled: "1",
        archive_before_delete: "1"
      }
    end

    it "does not render slug as a user-editable field" do
      get new_project_quick_path

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML.parse(response.body)

      expect(document.at_css("input[name='project[slug]']")).to be_nil
      expect(document.at_css("select[name='project[integration_kind]']")).to be_nil
      expect(document.css(".integration-choice-title").map(&:text)).to eq([
        "Manual / HTTP API",
        "Cloudflare Pages",
        "Android app",
        "iOS app",
        "Ruby gem",
        ".NET / ASP.NET Core",
        "JavaScript / TypeScript",
        "Python",
        "CFML"
      ])
      expect(document.css(".integration-choice-panel").map(&:text).join(" ")).to include(
        "Ruby gem",
        ".NET / ASP.NET Core",
        "CFML",
        "JavaScript / TypeScript",
        "Python",
        "Cloudflare Pages",
        "Android app",
        "iOS app",
        "Manual / HTTP API"
      )
      expect(document.css("[data-tg-group='project-new']").map { |node| node["data-tg-title"] }).to eq([
        "Name the app",
        "Choose integration type",
        "Choose retention policy"
      ])
      expect(document.css("[data-tg-group='project-new']").map { |node| node["data-tg-tour"] }.join(" ")).to include(
        "Enter a clear name",
        "runtime or manual HTTP path",
        "first event",
        "whether retained data must be archived before deletion"
      )
      expect(document.at_css("input[name='project[integration_kind]'][type='radio'][checked]")["value"]).to eq("ruby")
      expect(document.at_css("select[name='project[retention_policy_attributes][hot_retention_days]']")).to be_present
      expect(document.at_css("select[name='project[retention_policy_attributes][trace_retention_days]']")).to be_present
      expect(document.at_css("select[name='project[retention_policy_attributes][error_retention_days]']")).to be_present
      expect(document.at_css("input[name='project[retention_policy_attributes][archive_enabled]'][type='checkbox']")).to be_present
      expect(document.at_css("input[name='project[retention_policy_attributes][archive_before_delete]'][type='checkbox']")).to be_present
      expect(document.at_css("[data-controller='retention-archive']")).to be_present
      expect(response.body).to include("Archive retained data")
      expect(response.body).to include("Require archive before deletion")
      expect(response.body.index('name="project[description]"')).to be < response.body.index("integration-picker")
      expect(response.body.index("integration-picker")).to be < response.body.index("Data retention")
      expect(document.at_css("input[name='project[monitor_this_installation]']")).to be_nil
    end

    it "offers application admins a Ruby-only local self-monitoring destination" do
      users(:one).update!(application_admin: true)

      get new_project_quick_path

      document = Nokogiri::HTML.parse(response.body)
      choice = document.at_css(".self-monitoring-destination")
      expect(choice).to be_present
      expect(choice.text).to include("Use this project to monitor this Logister installation")
      expect(choice.at_css("input[name='project[monitor_this_installation]'][type='checkbox']")).to be_present
      expect(response.body.index("integration-picker")).to be < response.body.index("self-monitoring-destination")
      expect(response.body.index("self-monitoring-destination")).to be < response.body.index("Data retention")
    end

    it "creates project with the selected retention policy and redirects" do
      expect {
        post projects_path, params: {
          project: {
            name: "New App",
            slug: "manual-change",
            description: "Desc",
            integration_kind: "http_api",
            retention_policy_attributes: retention_policy_attributes
          }
        }
      }.to change(Project, :count).by(1)
        .and change(ProjectRetentionPolicy, :count).by(1)

      project = Project.last
      expect(response).to redirect_to(setup_step_project_path(project, group: "receive_data", step: "api_key"))
      expect(project.slug).to eq("new-app")
      expect(project.integration_kind).to eq("http_api")
      expect(project.retention_policy).to have_attributes(
        hot_retention_days: 60,
        trace_retention_days: 90,
        error_retention_days: 180,
        archive_enabled: true,
        archive_before_delete: true
      )
      follow_redirect!
      expect(response.body).to include("Project created")
      expect(response.body).to include("Setup: Start receiving data", "API key", "Generate key")
      expect(response.body).to include("HTTP API docs")
    end

    it "creates and connects a local self-monitoring project for an application admin" do
      users(:one).update!(application_admin: true)
      allow(InstanceConfiguration::Runtime).to receive(:apply!)

      expect {
        post projects_path, params: {
          project: {
            name: "Logister Self Monitoring",
            integration_kind: "ruby",
            monitor_this_installation: "1",
            retention_policy_attributes: retention_policy_attributes
          }
        }
      }.to change(Project, :count).by(1)
        .and change(ApiKey, :count).by(1)

      project = Project.find_by!(name: "Logister Self Monitoring")
      installation = Installation.current.reload
      expect(response).to redirect_to(setup_step_project_path(project, group: "receive_data", step: "first_event"))
      expect(flash[:notice]).to include("connected for local self-monitoring")
      expect(installation.self_monitoring_project).to eq(project)
      expect(installation.self_monitoring_api_key.project).to eq(project)
      expect(Logister::SelfMonitoringStatus.new(project: project, installation: installation)).to be_connected

      follow_redirect!
      expect(response.body).to include("Monitor this Logister installation safely", "Connected")
      expect(response.body).not_to include("Install the <code>logister-ruby</code> gem")
    end

    it "rejects a forged self-monitoring choice from a non-admin" do
      expect {
        post projects_path, params: {
          project: {
            name: "Unauthorized Self Monitoring",
            integration_kind: "ruby",
            monitor_this_installation: "1",
            retention_policy_attributes: retention_policy_attributes
          }
        }
      }.not_to change(Project, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Application admin access is required")
    end

    it "rejects a non-Ruby project as the local self-monitoring destination" do
      users(:one).update!(application_admin: true)

      expect {
        post projects_path, params: {
          project: {
            name: "Invalid Self Monitoring",
            integration_kind: "python",
            monitor_this_installation: "1",
            retention_policy_attributes: retention_policy_attributes
          }
        }
      }.not_to change(Project, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must be Ruby when monitoring this Logister installation")
    end

    it "does not create an active project when retention settings are omitted" do
      expect {
        post projects_path, params: {
          project: {
            name: "New App",
            description: "Desc",
            integration_kind: "http_api"
          }
        }
      }.not_to change(Project, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Choose a data retention policy before creating the project.")
    end

    it "renders new with retention validation errors" do
      expect {
        post projects_path, params: {
          project: {
            name: "New App",
            integration_kind: "ruby",
            retention_policy_attributes: retention_policy_attributes.merge(
              archive_enabled: "0",
              archive_before_delete: "1"
            )
          }
        }
      }.not_to change(Project, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Data retention")
      expect(response.body).to include("requires Archive retained data to be enabled")
    end

    it "renders new with errors when invalid" do
      post projects_path, params: {
        project: {
          name: "",
          retention_policy_attributes: retention_policy_attributes
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /projects/:uuid" do
    context "when owner" do
      before { sign_in users(:one) }

      it "tombstones the project and queues an audited cross-store purge" do
        project = projects(:one)
        api_key = project.api_keys.active.first
        clear_enqueued_jobs

        expect {
          delete project_path(project)
        }.to change(ProjectPurge, :count).by(1)
          .and change(Project, :count).by(0)

        expect(response).to redirect_to(projects_path)
        expect(project.reload).to be_archived
        expect(project).to be_purge_pending
        expect(api_key.reload.revoked_at).to be_present if api_key
        purge = ProjectPurge.find_by!(project_uuid: project.uuid)
        expect(purge.steps.order(:position).pluck(:store_name)).to eq(ProjectPurge::STORE_ORDER)
        expect(ProjectPurgeJob).to have_been_enqueued.with(purge.id)
      end
    end

    context "when shared member" do
      before { sign_in users(:two) }

      it "returns 404 and does not delete" do
        expect {
          delete project_path(projects(:one))
        }.not_to change(Project, :count)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /projects/:uuid/archive" do
    context "when owner" do
      before { sign_in users(:one) }

      it "archives the project and redirects to active projects" do
        project = projects(:one)
        api_key = api_keys(:one)

        patch archive_project_path(project)

        expect(response).to redirect_to(projects_path)
        expect(project.reload).to be_archived
        expect(api_key.reload.revoked_at).to be_present
      end
    end

    context "when shared member" do
      before { sign_in users(:two) }

      it "returns 404 and does not archive" do
        project = projects(:one)

        patch archive_project_path(project)

        expect(response).to have_http_status(:not_found)
        expect(project.reload).not_to be_archived
      end
    end
  end

  describe "PATCH /projects/:uuid/restore" do
    context "when owner" do
      before { sign_in users(:one) }

      it "restores an archived project" do
        project = create(:project, :archived, user: users(:one))

        patch restore_project_path(project)

        expect(response).to redirect_to(project_path(project))
        expect(project.reload).not_to be_archived
      end
    end
  end
end

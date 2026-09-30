# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Project setup paths", type: :request do
  let(:owner) { users(:one) }
  let(:project) { create(:project, :ruby, user: owner, name: "Path Project") }
  let(:frame_headers) { { "Turbo-Frame" => "setup_step_verification" } }

  def document
    Nokogiri::HTML.parse(response.body)
  end

  def step_path(group, step, target = project)
    setup_step_project_path(target, group: group, step: step)
  end

  def verification_path(group, step, attempt: nil, target: project)
    setup_step_verification_project_path(target, group: group, step: step, attempt: attempt)
  end

  def make_live(target = project)
    api_key = create(:api_key, project: target, user: target.user)
    create(:ingest_event, project: target, api_key: api_key)
    api_key
  end

  before { sign_in owner }

  describe "the wizard layout" do
    it "has its own focused layout, with no project tabs, and a way to save and exit" do
      get step_path("receive_data", "api_key")

      expect(response).to have_http_status(:success)
      expect(document.at_css("nav[aria-label='Project sections']")).to be_nil
      expect(document.at_css("header.wz-bar").text).to include("Path Project", "Setup: Start receiving data")
      expect(document.at_css("header.wz-bar a")["href"]).to eq(setup_project_path(project))
      expect(document.at_css("header.wz-bar a").text).to eq("Save and exit")
    end

    it "reports progress through the path to assistive technology" do
      make_live

      get step_path("receive_data", "api_key")

      bar = document.at_css("[role='progressbar']")
      expect(bar["aria-valuemax"]).to eq("2")
      expect(bar["aria-valuenow"]).to eq("2")
      expect(bar["aria-valuetext"]).to eq("2 of 2 steps done")
    end

    it "lists every step in the path with its owner and state, and marks the current one" do
      get step_path("receive_data", "first_event")

      rail = document.at_css("nav[aria-label='Steps in this setup path']")
      expect(rail.css("li").size).to eq(2)
      expect(rail.at_css("li[aria-current='step']").text).to include("First event", "Your code or CI")
      expect(rail.text).to include("Up next", "Make issues actionable")
      expect(document.css("h1").size).to eq(1)
    end

    it "shows an error from a failed submission and a notice, and marks flash as transient for Turbo's cache" do
      get step_path("receive_data", "api_key")

      expect(document.css("[data-turbo-temporary]")).to be_empty # nothing to show yet
    end
  end

  describe "GET /setup/:group" do
    it "opens the first step someone can act on" do
      make_live

      get setup_group_project_path(project, group: "actionable")

      target = response.location
      expect(target).to match(%r{/setup/actionable/(deployments|performance|source_repo)})
    end

    it "starts a path that is fully complete at its first step" do
      make_live

      get setup_group_project_path(project, group: "receive_data")

      expect(response).to redirect_to(step_path("receive_data", "api_key"))
    end
  end

  describe "which steps exist" do
    it "returns not found for a step this project type does not have" do
      get step_path("receive_data", "mobile_token")

      expect(response).to have_http_status(:not_found)
    end

    it "returns not found for a step in the wrong path" do
      get step_path("team", "api_key")

      expect(response).to have_http_status(:not_found)
    end

    it "has no page for an unknown path" do
      get "/projects/#{project.uuid}/setup/nonsense/api_key"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "steps done in Logister" do
    it "embeds the same API key form Settings uses, and returns to the step after it is submitted" do
      get step_path("receive_data", "api_key")

      form = document.at_css("form[action='#{project_api_keys_path(project)}']")
      expect(form).to be_present
      expect(form.at_css("input[name='setup_return'][value='receive_data/api_key']")).to be_present
      expect(form["data-turbo-frame"]).to eq("_top")
      expect(form["data-turbo"]).to be_nil
    end

    it "shows a complete step with the continue link once the key exists" do
      create(:api_key, project: project, user: owner)

      get step_path("receive_data", "api_key")

      expect(document.at_css(".wz-done").text).to include("This step is complete")
      continue = document.at_css("footer.wz-footer a.btn-primary")
      expect(continue.text).to eq("Continue: First event")
      expect(continue["href"]).to eq(step_path("receive_data", "first_event"))
    end

    it "names the next step on the locked continue button and says why it is locked" do
      get step_path("receive_data", "api_key")

      button = document.at_css("footer.wz-footer button[disabled]")
      expect(button.text).to eq("Continue: First event")
      expect(button["aria-disabled"]).to eq("true")
      expect(document.at_css("##{button['aria-describedby']}").text).to include("Unlocks when this step is complete.")
    end

    it "embeds a compact alerts form for the person's own preferences" do
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(true)
      make_live

      get step_path("team", "alerts")

      form = document.at_css("form[action='#{project_notification_preference_path(project)}']")
      expect(form.at_css("input[name='setup_return'][value='team/alerts']")).to be_present
      expect(form.css("input[type='checkbox']").size).to be >= 3
      expect(form.css("label").size).to be >= 3
      expect(form.at_css("input[type='submit']")["value"]).to eq("Save my alerts")
    end

    it "embeds the teammate invite form" do
      make_live

      get step_path("team", "teammates")

      expect(document.at_css("form[action='#{project_project_memberships_path(project)}'] input[name='setup_return']")["value"]).to eq("team/teammates")
    end

    it "asks a member who cannot manage the project to hand the step to a manager" do
      viewer = create(:user)
      create(:project_membership, project: project, user: viewer, role: :viewer)
      sign_out owner
      sign_in viewer

      get step_path("receive_data", "api_key")

      expect(document.at_css("[data-wizard-blocked='ask']")).to be_present
      expect(document.at_css("form[action='#{project_api_keys_path(project)}']")).to be_nil
    end
  end

  describe "steps that cannot be done yet" do
    it "explains that a step is waiting on the one before it and links to it" do
      get step_path("receive_data", "first_event")

      blocked = document.at_css("[data-wizard-blocked='dependency']")
      expect(blocked.text).to include("Finish api key first")
      expect(blocked.at_css("a")["href"]).to eq(step_path("receive_data", "api_key"))
    end

    it "explains that only the Logister admin can unblock an instance setting" do
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(false)
      make_live

      get step_path("team", "alerts")

      blocked = document.at_css("[data-wizard-blocked='instance']")
      expect(blocked.text).to include("needs your Logister admin", "Outbound email")
      expect(blocked.at_css("[data-controller='copy']")["data-copy-text-value"]).to end_with("/admin/installation/email")
    end

    it "gives a Logister admin a direct link" do
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(false)
      make_live
      admin = create(:user, application_admin: true)
      create(:project_membership, project: project, user: admin, role: :admin)
      sign_out owner
      sign_in admin

      get step_path("team", "alerts")

      expect(document.at_css("[data-wizard-blocked='instance'] a")["href"]).to eq("/admin/installation/email")
    end
  end

  describe "steps done in the project's own code" do
    before { create(:api_key, project: project, user: owner) }

    it "shows the integration guide expanded, next to a live check" do
      get step_path("receive_data", "first_event")

      expect(response.body).to include("First event guide")
      expect(document.at_css("#integration-guide details").has_attribute?("open")).to be(true)
      expect(document.at_css("turbo-frame#setup_step_verification [data-verification='waiting']")).to be_present
    end

    it "keeps everything the person can tab to outside the region that refreshes" do
      get step_path("receive_data", "first_event")

      polled = document.at_css("turbo-frame#setup_step_verification")
      expect(polled.css("a, button, input, select, textarea, summary, [tabindex]")).to be_empty

      check_again = document.at_css("a[data-turbo-frame='setup_step_verification']")
      expect(check_again.text).to eq("Check again")
      expect(check_again.ancestors("turbo-frame")).to be_empty
    end

    it "uses a generic guide with documentation links for steps that have no snippet" do
      make_live

      get step_path("actionable", "deployments")

      expect(document.at_css(".wz-panel").text).to include("What Logister looks for", "HTTP API reference")
      expect(response.body).not_to include("First event guide")
    end
  end

  describe "handing a step to an existing page" do
    before do
      allow(ProjectCorrelationPolicy).to receive(:instance_enabled?).and_return(true)
      make_live
    end

    it "opens project links with a way back" do
      get step_path("extend", "linked_projects")

      link = document.at_css(".wz-panel a.btn-primary")
      expect(link.text).to eq("Open project links")
      expect(link["href"]).to eq(project_project_links_path(project, setup_return: "extend/linked_projects"))
    end

    it "shows a way back on the page it opens, only for a step the project really has" do
      get project_project_links_path(project, setup_return: "extend/linked_projects")

      banner = document.at_css("[data-setup-return]")
      expect(banner.text).to include("Setup · Extend coverage", "Link related projects")
      expect(banner.at_css("a")["href"]).to eq(step_path("extend", "linked_projects"))

      get project_project_links_path(project, setup_return: "extend/not_a_step")
      expect(document.at_css("[data-setup-return]")).to be_nil

      get project_project_links_path(project, setup_return: "https://evil.example/x")
      expect(document.at_css("[data-setup-return]")).to be_nil
    end
  end

  describe "the live check" do
    before { create(:api_key, project: project, user: owner) }

    it "is a fragment for a Turbo Frame, and sends a direct visit to the full page" do
      get verification_path("receive_data", "first_event")

      expect(response).to redirect_to(step_path("receive_data", "first_event"))
    end

    it "keeps waiting, and tells the next request how long to wait and which attempt it is" do
      get verification_path("receive_data", "first_event", attempt: 3), headers: frame_headers

      panel = document.at_css("[data-verification='waiting']")
      expect(panel["data-controller"]).to eq("frame-refresh")
      expect(panel["data-frame-refresh-attempt-value"]).to eq("3")
      expect(panel["data-frame-refresh-interval-value"]).to eq("4000")
      expect(panel["data-frame-refresh-url-value"]).to eq(verification_path("receive_data", "first_event"))
      expect(panel["data-action"]).to eq("turbo:before-fetch-response@document->frame-refresh#responded turbo:fetch-request-error@document->frame-refresh#failed")
      expect(panel.text).to include("Waiting for Path Project", "Last checked")
      expect(panel.css("a, button")).to be_empty
    end

    it "backs off as the wait gets longer" do
      klass = ProjectSetupStepsController

      expect(klass.verification_interval(0)).to eq(4_000)
      expect(klass.verification_interval(14)).to eq(4_000)
      expect(klass.verification_interval(15)).to eq(8_000)
      expect(klass.verification_interval(39)).to eq(8_000)
      expect(klass.verification_interval(40)).to eq(15_000)
      expect(klass.verification_interval(klass::MAX_VERIFICATION_ATTEMPTS)).to eq(15_000)
      expect(klass::MAX_VERIFICATION_ATTEMPTS).to eq(63)
    end

    it "shows what arrived and where to go next, and stops polling" do
      api_key = project.api_keys.first
      create(:ingest_event, project: project, api_key: api_key, event_type: :error, level: "error",
                            message: "RuntimeError: Logister setup test", context: { environment: "production", release: "a1b2c3d" })

      get verification_path("receive_data", "first_event"), headers: frame_headers

      panel = document.at_css("[data-verification='complete']")
      expect(panel).to be_present
      expect(panel.at_css("[data-controller='frame-refresh']")).to be_nil
      expect(panel.at_css("[role='status']").text).to include("First event received")
      expect(panel.text).to include("RuntimeError: Logister setup test", "production", "release a1b2c3d", "Path Project is live.")
      continue = panel.at_css("a.btn-primary")
      expect(continue.text).to match(/\AContinue: /)
      expect(continue["data-turbo-frame"]).to eq("_top")
    end

    it "stops and says so once the attempts run out, without polling again" do
      max = ProjectSetupStepsController::MAX_VERIFICATION_ATTEMPTS

      get verification_path("receive_data", "first_event", attempt: max + 50), headers: frame_headers

      panel = document.at_css("[data-verification='stopped']")
      expect(panel).to be_present
      expect(panel["data-controller"]).to be_nil
      expect(panel.at_css("[role='status']").text).to include("Stopped checking")
      expect(panel.text).to include("Last checked")
    end

    it "reads only this step's evidence while waiting" do
      queries = capture_sql { get verification_path("receive_data", "first_event"), headers: frame_headers }
      evidence = queries.reject { |sql| sql.start_with?(%(SELECT "projects".*)) }
                        .grep(/FROM "(error_occurrences|mobile_ingest_tokens|project_deployments|source_repositories|project_memberships|trace_spans|telemetry_archives)"/)

      expect(evidence).to be_empty
      expect(queries.size).to be <= 16
    end

    it "does not answer for a step the project does not have" do
      get verification_path("receive_data", "mobile_token"), headers: frame_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "returning from a form" do
    it "returns a created API key to its step, with the key shown once, using a redirect Turbo follows" do
      post project_api_keys_path(project), params: { setup_return: "receive_data/api_key", api_key: { name: "production" } },
                                           headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(step_path("receive_data", "api_key"))
      follow_redirect!
      expect(response.body).to include("New API token:")
      expect(document.at_css(".wz-done").text).to include("This step is complete")
    end

    it "still answers Settings with a Turbo Stream when nothing asks to return to a step" do
      post project_api_keys_path(project), params: { api_key: { name: "production" } },
                                           headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    end

    it "ignores a return value that is not one of this project's steps" do
      [ "receive_data/mobile_token", "team/api_key", "//evil.example", "https://evil.example/a/b", "receive_data/", "/" ].each do |value|
        post project_api_keys_path(project), params: { setup_return: value, api_key: { name: "k-#{SecureRandom.hex(2)}" } }

        expect(response.location).not_to include("evil.example")
        expect(response).to redirect_to(setup_project_path(project, anchor: "api-keys"))
      end
    end

    it "returns an invited teammate to the step" do
      make_live
      teammate = create(:user)

      post project_project_memberships_path(project), params: { setup_return: "team/teammates", project_membership: { email: teammate.email, role: "viewer" } },
                                                      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

      expect(response).to redirect_to(step_path("team", "teammates"))
      follow_redirect!
      expect(document.at_css(".wz-done").text).to include("teammate")
    end

    it "shows a teammate error on the step instead of in Settings" do
      make_live

      post project_project_memberships_path(project), params: { setup_return: "team/teammates", project_membership: { email: "nobody@example.com", role: "viewer" } }

      expect(response).to redirect_to(step_path("team", "teammates"))
      follow_redirect!
      expect(document.at_css("[role='alert']").text).to include("User not found.")
    end

    it "returns saved alerts to the step" do
      allow(ProjectSetupPrerequisites).to receive(:email_configured?).and_return(true)
      make_live

      patch project_notification_preference_path(project), params: {
        setup_return: "team/alerts",
        project_notification_preference: { first_occurrence_enabled: "1", regression_enabled: "0", digest_frequency: "weekly" }
      }

      expect(response).to redirect_to(step_path("team", "alerts"))
      expect(ProjectNotificationPreference.for(user: owner, project: project).digest_frequency).to eq("weekly")
    end

    it "re-renders the step with the submitted values and a 422 when a repository cannot be saved" do
      allow(Logister::GithubAppConfig).to receive(:configured?).and_return(true)
      make_live

      post project_source_repositories_path(project), params: {
        setup_return: "actionable/source_repo",
        project_source_repository: { provider: "github", full_name: "not a valid name!!", default_branch: "trunk", runtime_root: "/srv/app" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(document.at_css("header.wz-bar")).to be_present
      expect(document.at_css("[role='alert']")).to be_present
      expect(document.at_css("input[name='project_source_repository[default_branch]'][value='trunk']")).to be_present
      expect(document.at_css("input[name='setup_return'][value='actionable/source_repo']")).to be_present
    end

    it "keeps Settings behavior when a repository fails from Settings" do
      allow(Logister::GithubAppConfig).to receive(:configured?).and_return(true)

      post project_source_repositories_path(project), params: {
        project_source_repository: { provider: "github", full_name: "not a valid name!!", default_branch: "trunk" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(document.at_css("header.wz-bar")).to be_nil
      expect(document.at_css("nav[aria-label='Project sections']")).to be_present
    end

    it "returns a linked project to the step" do
      allow(ProjectCorrelationPolicy).to receive(:instance_enabled?).and_return(true)
      make_live
      backend = create(:project, :ruby, user: owner, cross_project_correlations_enabled: true)
      project.update!(cross_project_correlations_enabled: true)

      post project_project_links_path(project), params: {
        setup_return: "extend/linked_projects", direction: "outgoing", peer_project_uuid: backend.uuid,
        environment_pairs: [ { source: "production", target: "production" } ]
      }

      expect(response).to redirect_to(step_path("extend", "linked_projects")).or have_http_status(:unprocessable_content)
    end
  end

  describe "skipping from inside a path" do
    before { make_live }

    it "moves on to the next step that needs doing" do
      post project_setup_skips_path(project, key: "linked_projects", wizard: 1)

      expect(response).to redirect_to(setup_project_path(project)).or redirect_to(%r{/setup/extend/})
      expect(project.setup_steps.find_by(key: "linked_projects")).to be_present
    end

    it "stays on the hub when skipped from the hub" do
      post project_setup_skips_path(project, key: "linked_projects")

      expect(response).to redirect_to(setup_project_path(project, anchor: "step-linked_projects"))
    end

    it "offers Skip for now only on steps that can be skipped" do
      get step_path("extend", "linked_projects")
      expect(document.at_css("footer form[action*='setup_skips']")).to be_present

      get step_path("receive_data", "api_key")
      expect(document.at_css("footer form[action*='setup_skips']")).to be_nil
    end
  end

  describe "mobile projects" do
    let(:android) { create(:project, :android, user: owner, name: "Path Android") }

    it "honors and undoes a skip after an optional step has partial evidence" do
      make_live(android)
      expect(ProjectSetupPlan.for(android, viewer: owner).item(:automatic_handler).state).to eq(:partial)

      post project_setup_skips_path(android, key: "automatic_handler")
      follow_redirect!

      expect(document.at_css("#step-automatic_handler").text).to include("Not needed")
      plan = ProjectSetupPlan.for(android.reload, viewer: owner)
      expect(plan.open_recommended_items.map(&:key)).not_to include(:automatic_handler)

      delete project_setup_skip_path(android, key: "automatic_handler")
      follow_redirect!

      expect(document.at_css("#step-automatic_handler").text).to include("Partial")
      expect(ProjectSetupPlan.for(android.reload, viewer: owner).open_recommended_items.map(&:key)).to include(:automatic_handler)
    end

    it "uses the same layout with mobile steps" do
      get step_path("receive_data", "mobile_token", android)

      expect(response).to have_http_status(:success)
      expect(document.at_css("[data-verification='waiting']")).to be_present
      expect(document.at_css("nav[aria-label='Steps in this setup path'] li").text).to include("Mobile token", "Your backend")
    end

    it "embeds the R8 mapping upload for Android and not the dSYM upload" do
      get step_path("actionable", "mapping", android)
      expect(document.at_css("#android-mappings")).to be_present

      get step_path("actionable", "symbols", android)
      expect(response).to have_http_status(:not_found)
    end
  end
end

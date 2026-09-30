# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Walkthroughs", type: :request do
  let(:owner) { users(:one) }
  let(:project) { create(:project, :ruby, user: owner, name: "Walk Project") }
  let(:api_key) { create(:api_key, project: project, user: owner) }
  let!(:group) do
    event = create(:ingest_event, project: project, api_key: api_key, event_type: :error, level: "error",
                                  message: "NoMethodError in CheckoutService", context: { environment: "production", release: "1.4.2" })
    ErrorGroupingService.call(event)
    project.error_groups.order(:id).last
  end

  def document
    Nokogiri::HTML.parse(response.body)
  end

  def step_path(step, target = project, uuid: group.uuid)
    walkthrough_step_project_path(target, key: "triage", step: step, group_uuid: uuid)
  end

  before { sign_in owner }

  describe "starting" do
    it "opens the first step on the newest open issue" do
      get walkthrough_project_path(project, key: "triage")

      expect(response).to redirect_to(step_path("read"))
    end

    it "explains why it cannot start when there is no open issue" do
      group.mark_resolved!

      get walkthrough_project_path(project, key: "triage")

      expect(response).to redirect_to(inbox_project_path(project))
      expect(flash[:alert]).to include("no open issues yet")
    end

    it "has no page for a walkthrough that does not exist" do
      get walkthrough_project_path(project, key: "made_up")

      expect(response).to have_http_status(:not_found)
    end

    it "does not open an issue that belongs to another project" do
      other_group = create(:error_group, project: create(:project, :ruby, user: owner))

      get step_path("read", uuid: other_group.uuid)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the layout" do
    it "is the focused wizard layout, with a way out that returns to the issue" do
      get step_path("read")

      expect(response).to have_http_status(:success)
      expect(document.at_css("nav[aria-label='Project sections']")).to be_nil
      bar = document.at_css("header.wz-bar")
      expect(bar.text).to include("Walk Project", "Walkthrough: Triage your first issue")
      expect(bar.at_css("a").text).to eq("Exit walkthrough")
      expect(bar.at_css("a")["href"]).to eq(inbox_project_path(project, group_uuid: group.uuid))
    end

    it "lists four steps, marks the current one, and keeps the issue in every link" do
      get step_path("owner")

      rail = document.at_css("nav[aria-label='Steps in this walkthrough']")
      expect(rail.css("li").size).to eq(4)
      expect(rail.at_css("li[aria-current='step']").text).to include("Assign an owner")
      expect(rail.css("a").map { |link| link["href"] }).to all(include("group_uuid=#{group.uuid}"))
      expect(document.at_css("[role='progressbar']")["aria-valuetext"]).to eq("2 of 4 steps done")
    end
  end

  describe "step 1: read the issue" do
    it "shows the real issue's facts and how to read it" do
      get step_path("read")

      expect(document.at_css("h1").text).to eq("Read the issue")
      panel = document.at_css("section[aria-labelledby='walkthrough-issue-title']")
      expect(panel.text).to include("NoMethodError in CheckoutService", "Occurrences", "production", "1.4.2")
      expect(document.text).to include("What to look at", "top application frame")
    end

    it "offers other open issues, and keeps the walkthrough on the one chosen" do
      event = create(:ingest_event, project: project, api_key: api_key, event_type: :error, level: "error", message: "Timeout in PaymentsGateway", fingerprint: "other-fp")
      ErrorGroupingService.call(event)
      other = project.error_groups.where.not(id: group.id).first

      get step_path("read")

      choice = document.at_css("details a")
      expect(choice["href"]).to eq(step_path("read", uuid: other.uuid))
    end
  end

  describe "step 2: check what shipped" do
    it "says plainly when no deploy is recorded, and points at recording them" do
      get step_path("shipped")

      expect(document.text).to include("No deploy to compare with")
      expect(document.at_css("a[href='#{setup_step_project_path(project, group: 'actionable', step: 'deployments')}']")).to be_present
    end

    it "compares the issue with a recorded deploy" do
      create(:project_deployment, project: project, release: "1.4.2", environment: "production", deployed_at: group.first_seen_at - 10.minutes)

      get step_path("shipped")

      expect(document.text).to include("Release 1.4.2", "first seen 10 minutes after that deploy", "exact release")
    end

    it "points a mobile project at its observed builds instead" do
      android = create(:project, :android, user: owner)
      key = create(:api_key, project: android, user: owner)
      event = create(:ingest_event, project: android, api_key: key, event_type: :error, level: "error", message: "Crash")
      ErrorGroupingService.call(event)
      android_group = android.error_groups.first

      get walkthrough_step_project_path(android, key: "triage", step: "shipped", group_uuid: android_group.uuid)

      expect(document.at_css("a[href='#{releases_project_path(android)}']")).to be_present
    end
  end

  describe "step 3: assign an owner" do
    let(:teammate) { create(:user, name: "Bob Builder") }

    before { create(:project_membership, project: project, user: teammate, role: :viewer) }

    it "offers the people who can own it and says what an owner does" do
      get step_path("owner")

      form = document.at_css("form[action='#{project_error_group_assignment_path(project, group)}']")
      expect(form.at_css("input[name='walkthrough_return'][value='triage/close']")).to be_present
      expect(form["data-turbo-frame"]).to eq("_top")
      expect(form.css("input[type='radio']").size).to eq(3)
      expect(form.at_css("input[type='radio'][checked]")["value"]).to eq("")
      expect(document.text).to include("My assignments")
    end

    it "assigns for real and returns to the next step, using a redirect Turbo follows" do
      patch project_error_group_assignment_path(project, group), params: { assigned_user_id: teammate.uuid, walkthrough_return: "triage/close" },
                                                                 headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(step_path("close"))
      expect(group.reload.assignee).to eq(teammate)
      follow_redirect!
      expect(document.at_css(".wz-flash-notice").text).to include("Assigned to Bob Builder")
    end

    it "still answers Issues with a Turbo Stream when nothing asks to return" do
      patch project_error_group_assignment_path(project, group), params: { assigned_user_id: teammate.uuid },
                                                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    end

    it "ignores a return value that is not a real walkthrough step" do
      [ "triage/nonsense", "nope/close", "https://evil.example/x", "//evil.example" ].each do |value|
        patch project_error_group_assignment_path(project, group), params: { assigned_user_id: teammate.uuid, walkthrough_return: value },
                                                                   headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end
    end

    it "shows who currently owns it" do
      group.assign_to!(teammate, assigned_by: owner)

      get step_path("owner")

      expect(document.text).to include("Currently:", "Bob Builder")
      expect(document.at_css("input[type='radio'][checked]")["value"]).to eq(teammate.uuid)
    end
  end

  describe "step 4: close the loop" do
    it "states what each choice does before it is taken" do
      get step_path("close")

      expect(document.text).to include("changes the issue for everyone", "reopen it any time")
      expect(document.at_css("form[action='#{resolve_project_error_group_path(project, group)}'] input[name='walkthrough_return'][value='triage/done']")).to be_present
      expect(document.at_css("form[action='#{ignore_project_error_group_path(project, group)}']")).to be_present
      expect(document.text).to include("Leave it open and finish. Nothing changes.")
    end

    it "resolves for real and returns to the finish screen" do
      patch resolve_project_error_group_path(project, group), params: { walkthrough_return: "triage/done" },
                                                              headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

      expect(response).to redirect_to(step_path("done"))
      expect(group.reload).to be_resolved
      follow_redirect!
      expect(document.at_css(".wz-flash-notice").text).to include("Marked resolved")
      expect(document.text).to include("Marked resolved.")
    end

    it "ignores for real" do
      patch ignore_project_error_group_path(project, group), params: { walkthrough_return: "triage/done" }

      expect(response).to redirect_to(step_path("done"))
      expect(group.reload).to be_ignored
    end

    it "still answers Issues with a Turbo Stream when nothing asks to return" do
      patch resolve_project_error_group_path(project, group), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    end
  end

  describe "the finish screen" do
    it "reports the issue's real state and offers what to do next" do
      get step_path("done")

      expect(document.at_css("h1").text).to eq("Done")
      expect(document.text).to include("Still open.", "Nobody is assigned yet.")
      expect(document.at_css("footer a.btn-primary").text).to eq("Back to Issues")
    end

    it "keeps working after the issue is closed, and offers another issue only when one is open" do
      group.mark_resolved!

      get step_path("done")

      expect(response).to have_http_status(:success)
      expect(document.text).to include("Marked resolved.")
      expect(document.text).not_to include("Triage another issue")
    end
  end

  it "has no page for a step that does not exist" do
    get step_path("nonsense")

    expect(response).to have_http_status(:not_found)
  end
end

RSpec.describe "The help menu", type: :request do
  let(:owner) { users(:one) }
  let(:project) { create(:project, :ruby, user: owner) }

  def document
    Nokogiri::HTML.parse(response.body)
  end

  def menu
    document.at_css(".help-menu")
  end

  before { sign_in owner }

  it "is a native disclosure that a small controller dismisses" do
    get inbox_project_path(project)

    expect(menu["data-controller"]).to eq("disclosure")
    expect(menu["data-action"]).to include("click@document->disclosure#closeOutside", "keydown.esc@document->disclosure#closeOnEscape", "turbo:before-cache@document->disclosure#close")
    expect(menu.at_css("details[data-disclosure-target='details'] summary")["aria-label"]).to eq("Help and walkthroughs")
  end

  it "offers the triage walkthrough on Issues once there is an issue to use" do
    api_key = create(:api_key, project: project, user: owner)
    ErrorGroupingService.call(create(:ingest_event, project: project, api_key: api_key, event_type: :error, level: "error"))

    get inbox_project_path(project)

    expect(menu.text).to include("Walkthroughs for Issues", "Triage your first issue", "4 steps")
    expect(menu.at_css("a[href='#{walkthrough_project_path(project, key: 'triage')}']")).to be_present
  end

  it "says what a walkthrough needs when it cannot start yet, without linking to a dead end" do
    get inbox_project_path(project)

    disabled = menu.at_css("[aria-disabled='true']")
    expect(disabled.text).to include("Triage your first issue", "Needs an open issue first")
    expect(menu.at_css("a[href*='walkthroughs']")).to be_nil
  end

  it "lists no walkthroughs on a section that has none" do
    get performance_project_path(project)

    expect(menu.text).not_to include("Walkthroughs for")
  end

  it "keeps the page tips and the integration docs reachable" do
    get project_path(project)

    expect(menu.at_css("button[data-action*='click->product-tour#start']").text).to include("Show page tips")
    expect(menu.at_css("a[target='_blank']")["rel"]).to include("noopener")
    expect(menu.text).to include("Ruby integration docs")
  end

  it "appears on setup pages, but not inside a wizard, where the exit is the only way out" do
    get setup_project_path(project)
    expect(menu).to be_present

    get setup_step_project_path(project, group: "receive_data", step: "api_key")
    expect(document.at_css(".help-menu")).to be_nil
  end
end

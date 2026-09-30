# frozen_string_literal: true

require "rails_helper"

# The live check is the one place the setup path depends on Turbo, Stimulus and
# time working together, so it is proven in a real browser: it notices evidence
# on its own, stops asking once it has it, and never takes focus from a control
# the person has tabbed to.
RSpec.describe "Project setup wizard", type: :system do
  let(:owner) { users(:one) }
  let(:project) { create(:project, :ruby, user: owner, name: "Wizard Project") }
  let!(:api_key) { create(:api_key, project: project, user: owner) }
  let(:step_path) { setup_step_project_path(project, group: "receive_data", step: "first_event") }

  def sign_in_user
    visit rails_health_check_path
    page.execute_script('window.localStorage.setItem("tg_tours_complete", "project-setup")')
    sign_in owner
  end

  # Counts server-side hits on the live-check endpoint.
  def track_verification_requests
    requests = Concurrent::AtomicFixnum.new(0)
    subscriber = ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*, payload|
      requests.increment if payload[:controller] == "ProjectSetupStepsController" && payload[:action] == "verification"
    end
    yield requests
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  before do
    allow(ProjectSetupStepsController).to receive(:verification_interval).and_return(300)
    sign_in_user
  end

  it "notices the first event on its own, offers the next step, and stops checking" do
    track_verification_requests do |requests|
      visit step_path

      expect(page).to have_css("[data-verification='waiting']")
      expect(page).to have_css("footer.wz-footer button[disabled]", text: /\AContinue: /)

      create(:ingest_event, project: project, api_key: api_key, event_type: :error, level: "error",
                            message: "RuntimeError: Logister setup test", context: { environment: "production" })

      within("turbo-frame#setup_step_verification") do
        expect(page).to have_css("[data-verification='complete']", wait: 10)
        expect(page).to have_text("RuntimeError: Logister setup test")
        expect(page).to have_css("a", text: /\AContinue: /)
      end
      expect(page).to have_css("[role='status']", text: "First event received", visible: :all)

      settled = requests.value
      sleep 1.5 # five intervals: a controller that kept polling would add several requests
      expect(requests.value).to eq(settled)
      expect(page).to have_no_css("[data-controller='frame-refresh']")
    end
  end

  it "keeps keyboard focus on Check again while the check refreshes" do
    track_verification_requests do |requests|
      visit step_path
      expect(page).to have_css("[data-verification='waiting']")

      page.execute_script("document.querySelector(\"a[data-turbo-frame='setup_step_verification']\").focus()")
      started = requests.value
      Timeout.timeout(5) { sleep 0.1 until requests.value >= started + 2 }

      expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq("Check again")
      expect(page).to have_css("[data-verification='waiting']")
    end
  end

  it "keeps checking after a request fails, and shows the evidence once it recovers" do
    original = Capybara.raise_server_errors
    Capybara.raise_server_errors = false
    failures = Concurrent::AtomicFixnum.new(0)
    allow(ProjectSetupPlan).to receive(:for_steps).and_wrap_original do |method, *args, **kwargs|
      raise "simulated failure" if failures.increment <= 2

      method.call(*args, **kwargs)
    end

    visit step_path
    expect(page).to have_css("[data-verification='waiting']")
    create(:ingest_event, project: project, api_key: api_key)

    expect(page).to have_css("[data-verification='complete']", wait: 15)
    expect(failures.value).to be >= 3
  ensure
    Capybara.raise_server_errors = original
  end

  it "checks straight away when asked, without leaving the page" do
    visit step_path
    expect(page).to have_css("[data-verification='waiting']")

    click_link "Check again"

    expect(page).to have_current_path(step_path)
    expect(page).to have_css("[data-verification='waiting']")
    expect(page).to have_css("h1", text: "First event")
  end

  it "does not poll a tab that is not visible" do
    track_verification_requests do |requests|
      visit step_path
      expect(page).to have_css("[data-verification='waiting']")
      page.execute_script("Object.defineProperty(document, 'hidden', { configurable: true, get: () => true })")
      before_hidden = requests.value
      sleep 1.2

      expect(requests.value - before_hidden).to be <= 1
      page.execute_script("delete document.hidden")
    end
  end

  it "walks from a completed step to the next one" do
    create(:ingest_event, project: project, api_key: api_key)
    visit step_path

    expect(page).to have_css("[data-verification='complete']")
    find("a", text: /\AContinue: /, match: :first).click

    expect(page).to have_css("header.wz-bar", text: "Setup: Make issues actionable")
    expect(page).to have_no_css("nav[aria-label='Project sections']")
  end
end

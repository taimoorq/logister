# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Triage walkthrough", type: :system do
  let(:owner) { users(:one) }
  let(:project) { create(:project, :ruby, user: owner, name: "Walkthrough Project") }
  let(:api_key) { create(:api_key, project: project, user: owner) }
  let(:teammate) { create(:user, name: "Bob Builder", email: "bob-walk@example.com") }
  let!(:group) do
    ErrorGroupingService.call(create(:ingest_event, project: project, api_key: api_key, event_type: :error, level: "error", message: "NoMethodError in CheckoutService"))
    project.error_groups.first
  end

  before do
    create(:project_membership, project: project, user: teammate, role: :viewer)
    visit rails_health_check_path
    page.execute_script('window.localStorage.setItem("tg_tours_complete", "project-errors")')
    sign_in owner
  end

  it "walks through an issue, and the choices really change it" do
    visit inbox_project_path(project)

    find(".help-menu-summary").click
    within(".help-menu-panel") { click_link "Triage your first issue" }

    expect(page).to have_css("h1", text: "Read the issue")
    expect(page).to have_css("header.wz-bar", text: "Walkthrough: Triage your first issue")
    expect(page).to have_text("NoMethodError in CheckoutService")

    click_link "Continue: Check what shipped"
    expect(page).to have_css("h1", text: "Check what shipped")

    click_link "Continue: Assign an owner"
    expect(page).to have_css("h1", text: "Assign an owner")
    choose "Bob Builder"
    click_button "Save assignment"

    expect(page).to have_css("h1", text: "Close the loop")
    expect(page).to have_css(".wz-flash-notice", text: "Assigned to Bob Builder")
    expect(group.reload.assignee).to eq(teammate)

    click_button "Mark as fixed"

    expect(page).to have_css("h1", text: "Done")
    expect(page).to have_text("Marked resolved.")
    expect(page).to have_text("Assigned to Bob Builder.")
    expect(group.reload).to be_resolved
    expect(page).to have_current_path(/walkthroughs\/triage\/done/)
  end

  it "can be left at any point with the issue unchanged" do
    visit walkthrough_step_project_path(project, key: "triage", step: "owner", group_uuid: group.uuid)

    click_link "Exit walkthrough"

    expect(page).to have_current_path(/inbox/)
    expect(group.reload).to be_unresolved
    expect(group.assignee).to be_nil
  end

  it "closes the help menu with Escape and returns focus to it" do
    visit inbox_project_path(project)

    find(".help-menu-summary").click
    expect(page).to have_css(".help-menu-panel", visible: :visible)

    page.driver.browser.action.send_keys(:escape).perform

    expect(page).to have_no_css(".help-menu details[open]")
    expect(page.evaluate_script("document.activeElement.classList.contains('help-menu-summary')")).to be(true)
  end

  it "closes the help menu when clicking elsewhere" do
    visit inbox_project_path(project)

    find(".help-menu-summary").click
    expect(page).to have_css(".help-menu details[open]")
    find("h1").click

    expect(page).to have_no_css(".help-menu details[open]")
  end
end

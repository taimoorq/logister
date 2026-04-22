# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project inbox", type: :system do
  include ActionView::RecordIdentifier

  def sign_in_via_browser(email:, password:)
    visit new_user_session_path
    fill_in "Email", with: email
    fill_in "Password", with: password
    click_button "Sign in"
  end

  it "updates the detail pane through Turbo when opening a different inbox row" do
    sign_in_via_browser(email: users(:one).email, password: "password123")

    visit project_path(projects(:system_inbox))
    expect(page).to have_content("System Inbox App inbox")

    within("turbo-frame#error_detail") do
      expect(page).to have_content("Primary inbox error")
    end

    click_link "Secondary inbox error"

    within("turbo-frame#error_detail") do
      expect(page).to have_content("Secondary inbox error")
      expect(page).to have_content("OrdersController#create")
    end

    expect(page).to have_css("tr##{dom_id(error_groups(:system_secondary_group))}[aria-selected='true']")
    expect(page).to have_css("tr##{dom_id(error_groups(:system_primary_group))}[aria-selected='false']")
  end

  it "switches detail tabs within the Turbo frame" do
    sign_in_via_browser(email: users(:one).email, password: "password123")

    visit project_path(projects(:system_inbox), group_uuid: error_groups(:system_primary_group).uuid)
    expect(page).to have_content("System Inbox App inbox")
    expect(page).to have_css("turbo-frame#error_detail")

    within("turbo-frame#error_detail") do
      expect(page).to have_content("Primary inbox error")
      click_link "Related logs (1)"
      expect(page).to have_css(".detail-tab[aria-current='page']", text: "Related logs (1)")
      expect(page).to have_content("Related log for the primary inbox error")
    end
  end
end

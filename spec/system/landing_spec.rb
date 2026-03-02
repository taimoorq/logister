# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Landing and dashboard", type: :system do
  it "shows the landing page when not signed in" do
    visit root_path
    expect(page).to have_content("Catch Rails bugs before your users do.")
    expect(page).to have_link(href: /logister-ruby/)
  end

  it "redirects to dashboard when signed in" do
    sign_in users(:one)
    visit root_path
    expect(page).to have_current_path(dashboard_path)
  end
end

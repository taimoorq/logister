# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project dashboard", type: :system do
  def sign_in_via_browser(email:, password:)
    visit new_user_session_path
    fill_in "Email", with: email
    fill_in "Password", with: password
    click_button "Sign in"
    expect(page).to have_current_path(dashboard_path)
  end

  it "renders the telemetry timeline chart on the overview dashboard" do
    sign_in_via_browser(email: users(:one).email, password: "password123")
    page.execute_script("window.localStorage.setItem('tg_tours_complete', JSON.stringify(['dashboard', 'project-overview']))")

    visit project_path(projects(:system_inbox))

    expect(page).to have_css(".project-telemetry-chart[data-rendered='true'] canvas", wait: 10)

    chart_box = page.evaluate_script(<<~JS)
      (() => {
        const element = document.querySelector(".project-telemetry-chart")
        const rect = element.getBoundingClientRect()
        return { width: rect.width, height: rect.height }
      })()
    JS

    expect(chart_box.fetch("width")).to be_positive
    expect(chart_box.fetch("height")).to be >= 300
  end
end

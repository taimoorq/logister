# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Product tours", type: :system do
  it "starts the tour automatically for new users on page load" do
    sign_in users(:one)

    visit dashboard_path

    expect(page).to have_css("#tg-dialog-next-btn", text: "Next")
  end

  it "keeps the primary tour action legible on its blue background" do
    sign_in users(:one)

    visit dashboard_path

    expect(page).to have_css("#tg-dialog-next-btn", text: "Next")

    computed_styles = page.evaluate_script(<<~JS)
      (function() {
        var button = document.querySelector("#tg-dialog-next-btn")
        var styles = window.getComputedStyle(button)
        return {
          backgroundColor: styles.backgroundColor,
          color: styles.color
        }
      })()
    JS

    expect(computed_styles).to include(
      "backgroundColor" => "rgb(37, 99, 235)",
      "color" => "rgb(255, 255, 255)"
    )
  end

  it "treats closing the tour as completed for future page loads" do
    sign_in users(:one)

    visit dashboard_path
    expect(page).to have_css("#tg-dialog-next-btn", text: "Next")

    find("#tg-dialog-close-btn").click

    expect(page).to have_no_css("#tg-dialog-next-btn")
    expect(page.evaluate_script("window.localStorage.getItem('tg_tours_complete')")).to include("dashboard")

    visit dashboard_path

    expect(page).to have_no_css("#tg-dialog-next-btn", wait: 1)
  end
end

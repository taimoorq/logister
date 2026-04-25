# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Landing and dashboard", type: :system do
  it "shows the landing page when not signed in" do
    visit root_path
    expect(page).to have_content("See errors, logs, and app health in one place.")
    expect(page).to have_content("Start free")
    expect(page).to have_link(href: /logister-ruby/)
  end

  it "keeps marketing screenshots inside their responsive frames" do
    visit root_path

    Capybara.using_wait_time(10) do
      page.document.synchronize do
        ready = page.evaluate_script(<<~JS)
          Boolean(
            window.Stimulus &&
            window.Stimulus.controllers.some((controller) => controller.identifier === "screenshots-slider")
          )
        JS
        raise Capybara::ExpectationNotMet, "expected screenshots slider controller to connect" unless ready
      end
    end

    metrics = page.evaluate_script(<<~JS)
      (function() {
        var frame = document.querySelector(".shot-wide.screenshots-slider")
        var track = document.querySelector(".screenshots-slider-track")
        var slide = document.querySelector(".screenshots-slide")
        var image = slide.querySelector("img")

        return {
          frameWidth: frame.getBoundingClientRect().width,
          frameHeight: frame.getBoundingClientRect().height,
          trackWidth: track.getBoundingClientRect().width,
          slideWidth: slide.getBoundingClientRect().width,
          imageWidth: image.getBoundingClientRect().width,
          imageHeight: image.getBoundingClientRect().height
        }
      })()
    JS

    expect(metrics.fetch("trackWidth")).to be_within(2).of(metrics.fetch("frameWidth"))
    expect(metrics.fetch("slideWidth")).to be_within(2).of(metrics.fetch("frameWidth"))
    expect(metrics.fetch("imageWidth")).to be <= metrics.fetch("frameWidth")
    expect(metrics.fetch("imageHeight")).to be <= metrics.fetch("frameHeight")
  end

  it "redirects to dashboard when signed in" do
    sign_in users(:one)
    visit root_path
    expect(page).to have_current_path(dashboard_path)
  end

  it "uses the nav state attributes for the mobile menu" do
    visit root_path
    page.current_window.resize_to(390, 844)
    Capybara.using_wait_time(10) do
      page.document.synchronize do
        ready = page.evaluate_script(<<~JS)
          Boolean(
            window.Stimulus &&
            window.Stimulus.controllers.some((controller) => controller.identifier === "nav")
          )
        JS
        raise Capybara::ExpectationNotMet, "expected nav Stimulus controller to connect" unless ready
      end
    end

    expect(page).to have_css("nav[data-nav-state='closed']", visible: :all)
    expect(page).to have_css("button[aria-controls='nav-menu-panel'][aria-expanded='false']", visible: :all)
    expect(page).to have_css("#nav-menu-panel.hidden[data-state='closed'][aria-hidden='true']", visible: :all)

    find("button[aria-controls='nav-menu-panel']", visible: :all).click

    expect(page).to have_css("nav[data-nav-state='open']", visible: :all)
    expect(page).to have_css("button[aria-controls='nav-menu-panel'][aria-expanded='true']", visible: :all)
    expect(page).to have_css("#nav-menu-panel[aria-hidden='false']")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Landing and dashboard", type: :system do
  it "shows the landing page when not signed in" do
    visit root_path
    expect(page).to have_content("Self-host error monitoring and bug triage with Logister.")
    expect(page).to have_content("forkable Rails app for grouped production errors")
    expect(page).to have_content("Versioned registry images")
    expect(page).to have_content("Read self-hosting docs")
    expect(page).to have_content("Use hosted app")
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

    screenshot_link = find("a.screenshot-fullsize-link[aria-label='Open full-size overview dashboard screenshot']", visible: :all)
    expect(screenshot_link[:href]).to match(%r{/assets/screenshots/public/dashboard-overview})
    expect(screenshot_link[:target]).to eq("_blank")
    expect(screenshot_link[:rel]).to include("noopener")

    slide_tab_stops = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(".screenshots-slide")).map(function(slide) {
        var link = slide.querySelector(".screenshot-fullsize-link")
        return {
          hidden: slide.getAttribute("aria-hidden"),
          tabindex: link ? link.getAttribute("tabindex") : null
        }
      })
    JS

    expect(slide_tab_stops.first.fetch("hidden")).to eq("false")
    expect(slide_tab_stops.first.fetch("tabindex")).to be_nil
    expect(slide_tab_stops.drop(1).map { |slide| slide.fetch("tabindex") }.uniq).to eq([ "-1" ])
  end

  it "redirects to dashboard when signed in" do
    sign_in users(:one)
    visit root_path
    expect(page).to have_current_path(dashboard_path)
  end

  it "opens the signed-in projects dropdown" do
    sign_in users(:one)
    page.current_window.resize_to(1400, 1400)
    visit dashboard_path

    find(".nav-project-menu summary", text: "Projects").click

    within(".nav-project-menu") do
      expect(page).to have_link(projects(:one).name, href: project_path(projects(:one)))
      expect(page).to have_link("All projects", href: projects_path)
      expect(page).to have_link("Add project", href: new_project_path)
    end

    find("body").send_keys(:escape)
    expect(page.evaluate_script("document.querySelector('.nav-project-menu').open")).to eq(false)
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
    expect(page).to have_css("#nav-menu-panel[data-state='closed'][aria-hidden='true']", visible: :all)
    expect(page.evaluate_script("getComputedStyle(document.querySelector('#nav-menu-panel')).display")).to eq("none")

    find("button[aria-controls='nav-menu-panel']", visible: :all).click

    expect(page).to have_css("nav[data-nav-state='open']", visible: :all)
    expect(page).to have_css("button[aria-controls='nav-menu-panel'][aria-expanded='true']", visible: :all)
    expect(page).to have_css("#nav-menu-panel[aria-hidden='false']")
  end
end

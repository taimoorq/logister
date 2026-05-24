# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mobile project review layouts", type: :system do
  TOUR_GROUPS = %w[
    dashboard
    dashboard-events
    event-detail
    projects-index
    project-overview
    project-errors
    project-insights
    project-performance
    project-activity
    project-monitors
    project-settings
    project-new
    project-edit
  ].freeze

  before do
    sign_in users(:one)
    visit dashboard_path
    page.current_window.resize_to(390, 844)
    page.execute_script("window.localStorage.setItem('tg_tours_complete', arguments[0])", TOUR_GROUPS.to_json)
  end

  def expect_page_to_fit_phone_viewport
    metrics = page.evaluate_script(<<~JS)
      (() => {
        const root = document.scrollingElement || document.documentElement
        return {
          clientWidth: Math.ceil(root.clientWidth),
          scrollWidth: Math.ceil(root.scrollWidth)
        }
      })()
    JS

    expect(metrics.fetch("scrollWidth")).to be <= metrics.fetch("clientWidth") + 2
  end

  it "keeps the dashboard explorer scrollable without widening the page" do
    visit dashboard_path

    expect(page).to have_css(".dashboard-explorer-main")

    metrics = page.evaluate_script(<<~JS)
      (() => {
        const explorer = document.querySelector(".dashboard-explorer-main")
        const layout = document.querySelector(".dashboard-explorer-layout")
        return {
          explorerClientWidth: Math.ceil(explorer.clientWidth),
          explorerScrollWidth: Math.ceil(explorer.scrollWidth),
          layoutWidth: Math.ceil(layout.getBoundingClientRect().width)
        }
      })()
    JS

    expect(metrics.fetch("explorerScrollWidth")).to be > metrics.fetch("explorerClientWidth")
    expect(metrics.fetch("layoutWidth")).to be > metrics.fetch("explorerClientWidth")
    expect_page_to_fit_phone_viewport
  end

  it "keeps project insights charts inside horizontal scroll regions" do
    visit insights_project_path(projects(:system_inbox))

    expect(page).to have_css(".mobile-chart-scroll .project-insights-chart", minimum: 2)

    chart_scrollers = page.evaluate_script(<<~JS)
      (() => Array.from(document.querySelectorAll(".mobile-chart-scroll")).map((element) => ({
        clientWidth: Math.ceil(element.clientWidth),
        scrollWidth: Math.ceil(element.scrollWidth)
      })))()
    JS

    expect(
      chart_scrollers.any? { |metrics| metrics.fetch("scrollWidth") > metrics.fetch("clientWidth") }
    ).to eq(true)
    expect_page_to_fit_phone_viewport
  end

  it "keeps setup code blocks readable on project settings" do
    visit settings_project_path(projects(:system_inbox))

    expect(page).to have_css("pre.mobile-x-scroll")

    code_metrics = page.evaluate_script(<<~JS)
      (() => {
        const element = document.querySelector("pre.mobile-x-scroll")
        return {
          clientWidth: Math.ceil(element.clientWidth),
          scrollWidth: Math.ceil(element.scrollWidth)
        }
      })()
    JS

    expect(code_metrics.fetch("scrollWidth")).to be > code_metrics.fetch("clientWidth")
    expect_page_to_fit_phone_viewport
  end

  it "keeps event detail tables contained in scroll wrappers" do
    visit inbox_project_path(projects(:system_inbox), group_uuid: error_groups(:system_primary_group).uuid)

    expect(page).to have_css(".detail-tabs")
    expect(page).to have_css(".mobile-x-scroll .occurrences-table", visible: :all)
    expect_page_to_fit_phone_viewport
  end
end

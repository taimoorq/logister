# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project dashboard", type: :system do
  it "renders the shared telemetry timeline card on the overview dashboard" do
    sign_in users(:one)
    visit dashboard_path
    page.execute_script("window.localStorage.setItem('tg_tours_complete', 'dashboard,project-overview')")

    visit project_path(projects(:system_inbox))

    expect(page).to have_css(".project-insights-metric-panel")
    expect(page).to have_css(".project-insights-chart-main[data-rendered='true'] canvas", wait: 10)
    expect(page).to have_css(".project-insights-active-chip", text: "Total events")

    chart_box = page.evaluate_script(<<~JS)
      (() => {
        const element = document.querySelector(".project-insights-chart-main")
        const rect = element.getBoundingClientRect()
        return { width: rect.width, height: rect.height }
      })()
    JS

    expect(chart_box.fetch("width")).to be_positive
    expect(chart_box.fetch("height")).to be >= 300

    find(".project-insights-series-toggle").click
    expect(page).to have_css(".project-insights-series-popover:not([hidden])")
    find("button[data-metric-key='logs.count']").click
    expect(page).to have_css(".project-insights-active-chip", text: "Logs")

    find(".project-insights-series-toggle").click
    expect(page).to have_no_css(".project-insights-series-popover:not([hidden])")
    find(".project-insights-active-chip[data-metric-key='logs.count']").click
    expect(page).to have_no_css(".project-insights-active-chip[data-metric-key='logs.count']")
  end
end

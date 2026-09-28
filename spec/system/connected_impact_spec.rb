require "rails_helper"

RSpec.describe "Connected impact investigation", type: :system do
  it "shows scoped impact and opens exact requests on desktop and narrow screens" do
    user = users(:one)
    app = create(:project, :ios, user:, name: "Storefront iOS", cross_project_correlations_enabled: true)
    backend = create(:project, user:, name: "Storefront API", cross_project_correlations_enabled: true)
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)
    ProjectLink.connect!(actor: user, source: app, target: backend, environment_pairs: [ { "source" => "production", "target" => "production" } ])
    error = create(:ingest_event, :grouped, project: app, message: "Checkout could not finish", context: { trace_id: "checkout", app: { version_name: "2.3", version_code: "23" }, release: "ios-2.3", installation: { id_hash: "synthetic-installation" } })
    span = create(:trace_span, project: backend, trace_id: "checkout", name: "POST /checkout", status: "error", context: { environment: "production", release: "api-8", http: { method: "POST", status_code: 503 } })
    create(:ingest_event, :grouped, project: backend, message: "Inventory unavailable", context: { trace_id: "checkout", release: "api-8" })
    sign_in user
    visit connections_project_path(app)
    expect(page).to have_text("1 affected installations")
    expect(page).to have_text("Matching request evidence observed")
    expect(page).to have_text("api-8")
    fill_in "This app's build", with: "23"
    click_button "Inspect evidence"
    expect(page).to have_field("This app's build", with: "23")
    expect(page).to have_text("1 affected installations")
    page.save_screenshot("/tmp/logister-connected-impact-desktop.png")
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    expect(page.evaluate_script("window.innerWidth")).to eq(390)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.save_screenshot("/tmp/logister-connected-impact-mobile.png")
    visit project_request_path(backend, span)
    expect(page).to have_text("Related error observed")
    find("summary", text: "Selected occurrence").send_keys(:enter)
    expect(page).to have_text("HTTP 503")
    expect(page).to have_text("180.5 ms")
    page.save_screenshot("/tmp/logister-connected-request-mobile.png")
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1100)
    page.save_screenshot("/tmp/logister-connected-request-desktop.png")
    visit inbox_project_path(app)
    click_link "Show connected evidence"
    expect(page).to have_text("1 with connected evidence")
    expect(page).to have_text("last 24 hours")
    expect(page).to have_link("Filter connected impact")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end

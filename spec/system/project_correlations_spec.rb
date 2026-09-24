require "rails_helper"

RSpec.describe "Connected requests", type: :system do
  it "connects projects and follows an occurrence in the browser" do
    source = create(:project, user: users(:one), integration_kind: "ios", name: "Mobile", cross_project_correlations_enabled: true)
    target = create(:project, user: users(:one), name: "Backend", cross_project_correlations_enabled: true)
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)
    event = create(:ingest_event, project: source, context: { trace_id: "request-trace" })
    related = create(:ingest_event, project: target, context: { trace_id: "request-trace", route: "GET /stories/:id" })
    sign_in users(:one)
    visit project_project_links_path(source)
    select "Backend — Ruby gem (#{target.slug})", from: "Backend project"
    click_button "Review connection"
    select "production", from: "App environment — Mobile"
    select "production", from: "Backend environment — Backend"
    click_button "Link projects"
    expect(page).to have_text("Mobile is now linked to Backend")
    visit correlations_project_event_path(source, event)
    expect(page).to have_text("Shared trace")
    expect(page).to have_link("Open occurrence", href: project_event_path(target, related))
    page.save_screenshot("/tmp/logister-correlations-desktop.png")
    page.current_window.resize_to(390, 844)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.save_screenshot("/tmp/logister-correlations-mobile.png")
    click_link "Open occurrence"
    expect(page).to have_current_path(project_event_path(target, related))
  end
  it "links Android and iOS from a Rails backend with explicit environments" do
    backend = create(:project, user: users(:one), name: "StoreStuff.app", cross_project_correlations_enabled: true)
    android = create(:project, :android, user: users(:one), name: "StoreStuff Android", cross_project_correlations_enabled: true)
    ios = create(:project, :ios, user: users(:one), name: "StoreStuff iOS", cross_project_correlations_enabled: true)
    create(:ingest_event, project: android, context: { environment: "release" })
    sign_in users(:one)
    visit project_project_links_path(backend)
    expect(page).to have_text("Link an app to this backend")
    picker = find("select#peer_project_uuid")
    picker.send_keys(:tab)
    expect(page.evaluate_script("getComputedStyle(document.querySelector('#peer_project_uuid')).borderTopWidth")).to eq("1px")
    page.save_screenshot("/tmp/logister-project-picker-desktop.png")
    select "#{android.name} — Android app (#{android.slug})", from: "App project"
    click_button "Review connection"
    expect(page).to have_text("StoreStuff Android sends requests to StoreStuff.app.")
    expect(page).to have_select("App environment — StoreStuff Android", selected: "Choose an environment")
    expect(page).to have_no_field("Other app environment")
    select "release", from: "App environment — StoreStuff Android"
    select "production", from: "Backend environment — StoreStuff.app"
    page.evaluate_async_script("Promise.all(document.getAnimations().map(animation => animation.finished.catch(() => {}))).then(arguments[0])")
    page.save_screenshot("/tmp/logister-project-link-review-desktop.png")
    page.current_window.resize_to(390, 844)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    expect(page.evaluate_script("window.innerWidth")).to eq(390)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.execute_script("document.querySelector('#link-project-title').scrollIntoView({ block: 'start', behavior: 'instant' })")
    page.save_screenshot("/tmp/logister-project-link-review-mobile.png")
    click_button "Link projects"
    expect(page).to have_text("StoreStuff Android is now linked to StoreStuff.app")
    select "#{ios.name} — iOS app (#{ios.slug})", from: "App project"
    click_button "Review connection"
    select "Other environment (enter name)", from: "App environment — StoreStuff iOS"
    fill_in "Other app environment", with: "testflight"
    select "staging", from: "Backend environment — StoreStuff.app"
    click_button "Link projects"
    expect(page).to have_text("StoreStuff iOS is now linked to StoreStuff.app")
    expect(ProjectLink.where(target_project: backend).pluck(:source_project_id)).to contain_exactly(android.id, ios.id)
    expect(ProjectLink.find_by!(source_project: ios).environment_pairs).to eq([ { "source" => "testflight", "target" => "staging" } ])
    expect(page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" }).to be_empty
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
  it "can review and link a custom environment without JavaScript" do
    driven_by :rack_test
    backend = create(:project, user: users(:one), name: "Rails backend")
    mobile = create(:project, :ios, user: users(:one), name: "iOS app")
    sign_in users(:one)
    visit project_project_links_path(backend)
    select "#{mobile.name} — iOS app (#{mobile.slug})", from: "App project"
    click_button "Review connection"
    select "Other environment (enter name)", from: "App environment — iOS app"
    fill_in "Other app environment", with: "qa-west"
    select "staging", from: "Backend environment — Rails backend"
    click_button "Link projects"
    expect(page).to have_text("iOS app is now linked to Rails backend")
    expect(ProjectLink.find_by!(source_project: mobile, target_project: backend).environment_pairs).to eq([
      { "source" => "qa-west", "target" => "staging" }
    ])
  end
end

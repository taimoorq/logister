require "rails_helper"

RSpec.describe "Connected requests", type: :system do
  it "connects projects and follows an occurrence in the browser" do
    source = create(:project, user: users(:one), name: "Mobile", cross_project_correlations_enabled: true)
    target = create(:project, user: users(:one), name: "Backend", cross_project_correlations_enabled: true)
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)
    event = create(:ingest_event, project: source, context: { trace_id: "request-trace" })
    related = create(:ingest_event, project: target, context: { trace_id: "request-trace", route: "GET /stories/:id" })
    sign_in users(:one)
    visit project_project_links_path(source)
    select "Backend", from: "Called project"
    click_button "Connect projects"
    expect(page).to have_text("Mobile calls Backend")
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
end

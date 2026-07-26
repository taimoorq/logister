# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "iOS project experience", type: :request do
  let(:payload) { JSON.parse(Rails.root.join("spec/fixtures/files/ios_error_payload.json").read) }
  let(:project) { create(:project, :ios, user: users(:one), name: "Acme iOS") }
  let(:api_key) { create(:api_key, project: project, user: users(:one)) }
  let!(:event) do
    create(
      :ingest_event,
      project: project,
      api_key: api_key,
      event_type: :error,
      level: payload.fetch("level"),
      message: payload.fetch("message"),
      context: payload.fetch("context")
    ).tap { |created_event| ErrorGroupingService.call(created_event) }
  end

  before { sign_in users(:one) }

  it "renders an iOS-specific experience through the shared profile contract" do
    get inbox_project_path(project, group_uuid: event.error_group.uuid)

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML.parse(response.body)
    expect(document.at_css("[data-project-experience='ios']")).to be_present
    expect(document.css(".detail-tab").map { |tab| tab.text.strip }).to eq([
      "Stack trace", "Trail", "Occurrences (1)", "App & device", "Raw"
    ])
    expect(document.text).to include("CheckoutError", "CheckoutViewModel.submit(_:)", "Symbols included", "Triggered thread", "Logister SDK")
    expect(document.at_css(".mobile-mechanism-badge").text).to include("Reported error")
    expect(document.at_css(".ios-incident-header")).to be_present
    expect(document.text).not_to include("Fatal", "Android")
    expect(document.text).to include("iPhone17,1", "iOS 19.0")
  end


  it "renders the same Apple diagnostic contract through the Turbo detail frame" do
    get project_event_path(
      project,
      event,
      event_occurred_at: event.occurred_at.utc.iso8601(6),
      group_uuid: event.error_group.uuid
    ), headers: { "Turbo-Frame" => "error_detail" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML.parse(response.body)
    expect(document.at_css("turbo-frame#error_detail[data-project-integration='ios']")).to be_present
    expect(document.at_css("[data-project-experience='ios']")).to be_present
    expect(document.text).to include("Reported error", "Logister SDK", "Symbols included", "App & device")
  end

  it "keeps iOS source, symbol, release, time, and sort state inside the Turbo inbox frame" do
    get inbox_project_path(
      project,
      filter: "all",
      sort: "impact",
      release: "com.acme.shop@4.2.0+310",
      diagnostic_source: "sdk",
      symbolication_status: "not_required",
      time_range: "30d"
    ), headers: { "Turbo-Frame" => "project_inbox" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML.parse(response.body)
    state_url = document.at_css("turbo-frame#project_inbox [data-inbox-state-url]")["data-inbox-state-url"]
    expect(document.at_css("turbo-frame#project_inbox .inbox-pane-header").text).to include("Stability issues", "impact")
    expect(state_url).to include(
      "diagnostic_source=sdk",
      "release=com.acme.shop%404.2.0%2B310",
      "sort=impact",
      "symbolication_status=not_required",
      "time_range=30d"
    )
  end

  it "preserves iOS profile state through Turbo Stream issue actions" do
    patch resolve_project_error_group_path(
      project,
      event.error_group,
      filter: "unresolved",
      release: "com.acme.shop@4.2.0+310",
      diagnostic_source: "sdk",
      symbolication_status: "not_required",
      time_range: "30d",
      sort: "recommended"
    ), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include(
      "data-inbox-state-url",
      "diagnostic_source=sdk",
      "symbolication_status=not_required",
      "time_range=30d",
      'method="morph"'
    )
  end

  it "shows a reusable setup checklist tailored to Apple monitoring health" do
    get setup_project_path(project)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(
      "First diagnostic",
      "App &amp; build",
      "Sessions",
      "Installations",
      "Breadcrumbs",
      "MetricKit",
      "dSYM coverage",
      "App Store"
    )
    expect(response.body).to include(
      "telemetry_schema_version",
      "reported_error",
      "handled_exception",
      "testflight"
    )
    expect(response.body).not_to include("NoMethodError in CheckoutService")
    expect(response.body).not_to include("R8", "Google Play")
  end
end

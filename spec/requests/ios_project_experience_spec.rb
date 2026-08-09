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
    expect(document.at_css("[data-project-experience='ios']")["data-project-experience-version"]).to eq("2")
    expect(document.css(".detail-tab").map { |tab| tab.text.strip }).to eq([
      "Reporting stack", "Trail", "Occurrences (1)", "App & device", "Raw"
    ])
    expect(document.text).to include("CheckoutError", "CheckoutViewModel.submit(_:)", "Symbols included", "Reporting thread", "Logister SDK")
    expect(document.at_css(".mobile-mechanism-badge").text).to include("Reported error")
    expect(document.at_css(".ios-incident-header")).to be_present
    expect(document.text).not_to include("Fatal", "Android")
    expect(document.text).to include("iPhone17,1", "iOS 19.0")
    expect(document.at_css(".mobile-row-type").text).to eq("Reported error")
    expect(document.at_css(".mobile-row-headline").text).to include("CheckoutError", "CheckoutViewModel.submit(_:)")
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
      symbolication_status: "symbols_included",
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
      "symbolication_status=symbols_included",
      "time_range=30d"
    )
  end

  it "keeps delayed CPU diagnostic fatality unknown and labels reporting versus receipt clocks" do
    received_at = Time.current.change(usec: 0)
    report_start = 2.days.ago.change(usec: 0)
    report_end = 1.day.ago.change(usec: 0)
    cpu_event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      event_type: :error,
      level: "warning",
      message: "CPU diagnostic",
      occurred_at: report_end,
      context: {
        "platform" => "ios",
        "telemetry_schema_version" => 3,
        "diagnostic" => {
          "source" => "metrickit",
          "kind" => "excessive_cpu",
          "measurements" => {
            "total_cpu_time" => { "value" => 98, "unit" => "seconds" },
            "sampled_time" => { "value" => 60, "unit" => "seconds" }
          },
          "call_stack_tree" => {
            "per_thread" => false,
            "stacks" => [ {
              "id" => "0",
              "name" => "Sampled path",
              "role" => "sampled",
              "attributed" => true,
              "sample_count" => 12,
              "root_frames" => [ {
                "image" => "AcmeShop",
                "relative_address" => "0x1240",
                "application_frame" => true,
                "sample_count" => 9,
                "subframes" => [ { "image" => "UIKitCore", "relative_address" => "0x28", "application_frame" => false } ]
              } ]
            } ]
          }
        },
        "error" => { "mechanism" => "resource_diagnostic", "handled" => false },
        "threads" => [ {
          "id" => "0",
          "name" => "Sampled path",
          "role" => "sampled",
          "attributed" => true,
          "triggered" => false,
          "frames" => [ { "image" => "AcmeShop", "relative_address" => "0x1240", "application_frame" => true } ]
        } ],
        "app" => { "identifier" => "com.acme.shop", "version_name" => "4.2.0", "version_code" => "310" },
        "telemetry_evidence" => {
          "schema_version" => 1,
          "source" => "metrickit",
          "kind" => "excessive_cpu",
          "evidence_kind" => "sampled_call_tree",
          "identity_scope" => "occurrence",
          "fatality" => "unknown",
          "time" => {
            "precision" => "reporting_interval",
            "reporting_start" => report_start.utc.iso8601,
            "reporting_end" => report_end.utc.iso8601,
            "received_at" => received_at.utc.iso8601
          }
        }
      }
    )
    ErrorGroupingService.call(cpu_event)

    get inbox_project_path(project, group_uuid: cpu_event.error_group.uuid)

    document = Nokogiri::HTML.parse(response.body)
    cpu_row = document.at_css("##{ActionView::RecordIdentifier.dom_id(cpu_event.error_group)}")
    expect(cpu_row.at_css(".mobile-row-type").text).to eq("Excessive CPU")
    expect(cpu_row.at_css(".mobile-row-headline").text).to include("Excessive CPU", "98 s CPU", "60 s sampled")
    expect(cpu_row.at_css(".mobile-row-fatality")).to be_nil
    expect(cpu_row.at_css(".error-meta-time").text).to include("reported through")
    expect(document.at_css(".detail-context-grid").text).to include("Reporting interval", "Received", "Time precision")
    expect(document.at_css(".detail-actionbar").text).not_to include("Fatal crash")
    expect(document.css(".detail-tab").map { |tab| tab.text.strip }).to include("Sampled call tree")
    expect(document.text).to include("Diagnostic measurement", "Sampled call tree", "aggregate sample tree", "12 samples", "9 samples")

    get inbox_project_path(project, diagnostic_kind: "excessive_cpu", time_range: "all")
    filtered = Nokogiri::HTML.parse(response.body)
    expect(filtered.css(".mobile-row-type").map { |node| node.text.strip }).to eq([ "Excessive CPU" ])
  end

  it "shows only blocking symbol coverage in the row while keeping successful coverage in detail" do
    symbol_event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      event_type: :error,
      message: "Address-only crash",
      context: {
        "platform" => "ios",
        "diagnostic" => { "source" => "sdk", "kind" => "crash" },
        "error" => { "mechanism" => "native_crash", "fatal" => true },
        "app" => { "identifier" => "com.acme.shop", "version_name" => "4.2.0", "version_code" => "310" },
        "device" => { "architecture" => "arm64" },
        "exception" => {
          "stacktrace" => [ {
            "image" => "AcmeShop",
            "image_uuid" => "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "address" => "0x1004a1290",
            "application_frame" => true
          } ]
        }
      }
    )
    ErrorGroupingService.call(symbol_event)

    get inbox_project_path(project, group_uuid: symbol_event.error_group.uuid)

    document = Nokogiri::HTML.parse(response.body)
    row = document.at_css("##{ActionView::RecordIdentifier.dom_id(symbol_event.error_group)}")
    expect(row.text).to include("dSYM missing")

    create(
      :apple_symbol_artifact,
      project: project,
      app_identifier: "com.acme.shop",
      version_code: "310",
      binary_uuid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      architecture: "arm64",
      status: "verified"
    )

    get inbox_project_path(project, group_uuid: symbol_event.error_group.uuid)

    document = Nokogiri::HTML.parse(response.body)
    row = document.at_css("##{ActionView::RecordIdentifier.dom_id(symbol_event.error_group)}")
    expect(row.text).not_to include("Verified dSYM matched")
    expect(document.at_css("turbo-frame#error_detail").text).to include("Verified dSYM matched")
  end

  it "preserves iOS profile state through Turbo Stream issue actions" do
    patch resolve_project_error_group_path(
      project,
      event.error_group,
      filter: "unresolved",
      release: "com.acme.shop@4.2.0+310",
      diagnostic_source: "sdk",
      symbolication_status: "symbols_included",
      time_range: "30d",
      sort: "recommended"
    ), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include(
      "data-inbox-state-url",
      "diagnostic_source=sdk",
      "symbolication_status=symbols_included",
      "time_range=30d",
      'method="morph"'
    )
  end

  it "uses memory evidence without rendering an empty stack workbench" do
    memory_event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      event_type: :error,
      message: "Memory-limit termination",
      context: {
        "platform" => "ios",
        "diagnostic" => { "source" => "sdk", "kind" => "memory_limit_termination" },
        "error" => { "mechanism" => "memory_termination", "fatal" => true },
        "termination" => { "namespace" => "JETSAM", "reason" => "per-process-limit" }
      }
    )
    ErrorGroupingService.call(memory_event)

    get inbox_project_path(project, group_uuid: memory_event.error_group.uuid)

    document = Nokogiri::HTML.parse(response.body)
    detail = document.at_css("turbo-frame#error_detail")
    expect(detail.css(".detail-tab").map { |tab| tab.text.strip }).to include("Memory evidence")
    expect(detail.text).to include("No stack applies to this evidence", "does not include an app call stack", "per-process-limit")
    expect(detail.at_css(".better-errors-workbench")).to be_nil
  end

  it "shows a reusable setup checklist tailored to Apple monitoring health" do
    get setup_project_path(project)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(
      "Connect",
      "Verify delivery",
      "Improve evidence",
      "External sources",
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

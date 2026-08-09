# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Android project experience", type: :request do
  let(:payload) { JSON.parse(Rails.root.join("spec/fixtures/files/android_error_payload.json").read) }
  let(:project) { create(:project, :android, user: users(:one), name: "Acme Android") }
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

  it "renders the Android inbox and detail contract from a current SDK payload" do
    get inbox_project_path(project, group_uuid: event.error_group.uuid, release: "1.4.0+42", sort: "impact")

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML.parse(response.body)

    expect(document.at_css(".inbox-pane-header").text).to include("Stability issues", "impact")
    expect(document.at_css("[data-project-experience='android']")).to be_present
    inbox_frame = document.at_css("turbo-frame#project_inbox")
    expect(inbox_frame["style"]).to include("view-transition-name: project-inbox")
    expect(inbox_frame.at_css("[data-inbox-state-url]")["data-inbox-state-url"]).to include("release=1.4.0%2B42", "sort=impact")
    expect(document.at_css("a.error-row-link")["data-turbo-action"]).to eq("advance")
    expect(document.css(".detail-tab").map { |tab| tab.text.strip }).to eq([
      "Stack trace",
      "Trail",
      "Occurrences (1)",
      "App & device",
      "Raw"
    ])
    expect(document.at_css(".mobile-mechanism-badge").text).to include("Reported exception")
    expect(document.text).to include(
      "java.lang.IllegalStateException",
      "com.acme.shop.checkout.CartRepository.save",
      "CartRepository.kt",
      "Mapping missing",
      "No R8 mapping matches"
    )
    expect(document.text).not_to include("Request info", "Local Variables", "Fatal")
    expect(document.at_css(".mobile-row-type").text).to eq("Reported exception")
    expect(document.at_css(".mobile-row-headline").text).to include("java.io.IOException", "CartStore.write")
    expect(document.at_css(".mobile-row-supporting").text).to include("CartStore.kt:19", "1.4.0 (42)")
    expect(document.at_css("section[aria-label='Scoped issue impact']")).to be_present
    expect(document.at_css("section[aria-label='Selected occurrence context']").text).to include("Selected occurrence", "1.4.0 (42)")

    resolve_form = document.css("form").find { |form| form.text.include?("Mark as fixed") }
    expect(resolve_form["action"]).to include("release=1.4.0%2B42", "sort=impact")
  end

  it "renders the same Android contract through the Turbo detail frame" do
    get project_event_path(
      project,
      event,
      event_occurred_at: event.occurred_at.utc.iso8601(6),
      group_uuid: event.error_group.uuid
    ), headers: { "Turbo-Frame" => "error_detail" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML.parse(response.body)
    expect(document.at_css("turbo-frame#error_detail[data-project-integration='android']")).to be_present
    expect(document.at_css("[data-project-experience='android']")).to be_present
    expect(document.text).to include("Reported exception", "App & device")
  end

  it "labels privacy-safe automatic crashes without inventing missing exception detail" do
    safe_payload = JSON.parse(Rails.root.join("spec/fixtures/files/android_safe_automatic_error_payload.json").read)
    safe_event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      event_type: :error,
      level: safe_payload.fetch("level"),
      message: safe_payload.fetch("message"),
      context: safe_payload.fetch("context")
    )
    ErrorGroupingService.call(safe_event)

    get inbox_project_path(project, group_uuid: safe_event.error_group.uuid)

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML.parse(response.body)
    expect(document.text).to include("Fatal", "Automatic capture", "message redacted")
    expect(document.text).not_to include("private nested detail", "bearer secret-value")
  end

  it "renders historical ApplicationExitInfo evidence without a fabricated stack" do
    exit_event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      event_type: :error,
      level: "error",
      message: "Android process exit: anr",
      context: {
        "platform" => "android",
        "error_mechanism" => "anr",
        "capture_source" => "historical_exit",
        "application_exit_reason" => 6,
        "application_exit_importance" => 100,
        "app" => { "package_name" => "com.acme.shop", "version_name" => "1.3.0", "version_code" => "41", "process" => "com.acme.shop" }
      }
    )
    ErrorGroupingService.call(exit_event)

    get inbox_project_path(project, group_uuid: exit_event.error_group.uuid)

    document = Nokogiri::HTML.parse(response.body)
    detail = document.at_css("turbo-frame#error_detail")
    expect(detail.text).to include("ApplicationExitInfo evidence", "No stack captured for this historical exit", "Importance", "100")
    expect(detail.at_css(".better-errors-workbench")).to be_nil
    exit_row = document.at_css("##{ActionView::RecordIdentifier.dom_id(exit_event.error_group)}")
    expect(exit_row.at_css(".mobile-row-type").text).to eq("ANR")
    expect(exit_row.at_css(".mobile-row-headline").text).to include("ANR", "6")
  end

  it "server-redacts the standard Raw view, including mobile correlation identities" do
    event.update!(
      context: event.context.deep_merge(
        "token" => "top-secret",
        "session" => { "id" => "session-raw" },
        "installation" => { "id_hash" => "installation-raw" }
      )
    )

    get inbox_project_path(project, group_uuid: event.error_group.uuid)

    document = Nokogiri::HTML.parse(response.body)
    raw = document.at_css("[data-redaction='server']")

    expect(raw.text).to include("Server-redacted event context", "[REDACTED]")
    expect(raw.text).not_to include("top-secret", "session-raw", "installation-raw")
  end

  it "returns the server-owned list header and filter state inside the Turbo frame" do
    get inbox_project_path(project, filter: "all", sort: "velocity", release: "1.4.0+42"),
        headers: { "Turbo-Frame" => "project_inbox" }

    document = Nokogiri::HTML.parse(response.body)
    expect(document.css("turbo-frame#project_inbox").size).to eq(1)
    expect(document.at_css("turbo-frame#project_inbox .inbox-pane-header").text).to include("Stability issues", "velocity")
    expect(document.at_css("turbo-frame#project_inbox [data-inbox-state-url]")["data-inbox-state-url"]).to include("filter=all", "release=1.4.0%2B42", "sort=velocity")
  end

  it "preserves profile filters and sort through Turbo Stream workflow actions" do
    patch resolve_project_error_group_path(
      project,
      event.error_group,
      filter: "unresolved",
      release: "1.4.0+42",
      sort: "impact"
    ), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("data-inbox-state-url", "release=1.4.0%2B42", "sort=impact")
    expect(response.body).to include('method="morph"')
  end

  it "renders matching R8 symbols throughout the issue detail" do
    context = event.context.deep_dup
    context["exception"]["stacktrace"] = [
      {
        "class_name" => "a",
        "method_name" => "b",
        "file_name" => "SourceFile.java",
        "line_number" => 3,
        "in_app" => true
      }
    ]
    context["exception"].delete("cause")
    event.update!(context: context)
    mapping_content = Rails.root.join("spec/fixtures/files/android_mapping.txt").binread
    create(
      :android_mapping_file,
      project: project,
      version_code: "42",
      content: mapping_content,
      byte_size: mapping_content.bytesize,
      checksum_sha256: Digest::SHA256.hexdigest(mapping_content)
    )

    get inbox_project_path(project, group_uuid: event.error_group.uuid)

    document = Nokogiri::HTML.parse(response.body)
    inbox_row = document.at_css("#project_inbox tr")
    expect(inbox_row.at_css(".mobile-row-headline").text).to include("com.acme.shop.storage.CartStore.write")
    expect(inbox_row.text).to include("CartStore.java")
    expect(inbox_row.text).not_to include("Frames deobfuscated")
    expect(document.text).to include("Frames deobfuscated", "com.acme.shop.storage.CartStore.write", "CartStore.java")
    expect(document.text).not_to include("a.b(SourceFile.java")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project inbox evidence signals", type: :request do
  it "renders one exact-clock spike signal and explains its comparison in detail" do
    now = Time.current.change(usec: 0)
    project = create(:project, :android)
    sign_in project.user
    api_key = create(:api_key, project:, user: project.user)
    group = create(:error_group, project:, created_at: 3.days.ago, updated_at: 3.days.ago)
    times = Array.new(5) { now - 30.hours } + Array.new(10) { now - 2.hours }
    times.each do |occurred_at|
      event = create(
        :ingest_event,
        project:,
        api_key:,
        occurred_at:,
        context: {
          "platform" => "android",
          "error" => { "mechanism" => "unhandled_exception" },
          "exception" => { "type" => "java.lang.IllegalStateException", "stacktrace" => [] },
          "telemetry_evidence" => {
            "source" => "sdk",
            "time" => { "precision" => "exact", "occurred_at" => occurred_at.iso8601 }
          }
        }
      )
      create(
        :error_occurrence,
        error_group: group,
        ingest_event: event,
        occurred_at:,
        ingest_event_occurred_at: occurred_at,
        dimensions: { "time_precision" => "exact" }
      )
    end

    get inbox_project_path(project, group_uuid: group.uuid)

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML.parse(response.body)
    row = document.at_css("##{ActionView::RecordIdentifier.dom_id(group)}")
    expect(row.at_css(".mobile-row-attention").text.strip).to eq("Spiking")
    expect(row.at_css(".mobile-row-attention-context").text.strip).to eq("+100% in 24h")
    expect(row.at_css(".mobile-row-attention")["title"]).to include(
      "10 exact-time events in the latest 24 hours",
      "5 in the prior 24 hours"
    )
    expect(document.at_css("turbo-frame#error_detail").text).to include("Spiking evidence", "+100% in 24h")
  end
end

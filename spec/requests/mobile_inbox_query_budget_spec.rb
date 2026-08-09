# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "mobile inbox query budget", type: :request do
  it "renders one hundred Android issues with a bounded, non-row-linear query count" do
    project = create(:project, :android, user: users(:one))
    api_key = create(:api_key, project:, user: users(:one))
    100.times do |index|
      occurred_at = (index + 1).minutes.ago
      event = create(
        :ingest_event,
        project:,
        api_key:,
        event_type: :error,
        occurred_at:,
        message: "Failure #{index}",
        context: {
          "platform" => "android",
          "app" => { "package_name" => "com.acme.shop", "version_name" => "1.0", "version_code" => "42" },
          "device" => { "model" => "Pixel 8" },
          "os" => { "name" => "Android", "version" => "15", "api_level" => 35 },
          "diagnostic" => { "source" => "sdk", "kind" => "reported_error" },
          "error" => { "mechanism" => "handled_exception", "fatal" => false },
          "exception" => {
            "type" => "java.lang.IllegalStateException",
            "stacktrace" => [ { "class_name" => "com.acme.CartStore", "method_name" => "write", "application_frame" => true } ]
          },
          "telemetry_evidence" => {
            "source" => "sdk",
            "kind" => "reported_error",
            "time" => { "precision" => "exact", "occurred_at" => occurred_at.utc.iso8601, "received_at" => occurred_at.utc.iso8601 }
          }
        }
      )
      group = create(
        :error_group,
        project:,
        title: "Failure #{index}",
        latest_event_id: event.id,
        latest_event_occurred_at: event.occurred_at,
        first_seen_at: occurred_at,
        last_seen_at: occurred_at,
        occurrence_count: 1
      )
      event.update_columns(error_group_id: group.id)
      create(
        :error_occurrence,
        error_group: group,
        ingest_event: event,
        occurred_at:,
        mechanism: "handled_exception",
        release: "com.acme.shop@1.0+42",
        dimensions: {
          "time_precision" => "exact",
          "diagnostic_source" => "sdk",
          "diagnostic_kind" => "reported_error",
          "device_model" => "Pixel 8",
          "os_version" => "15",
          "materialization_version" => ErrorOccurrenceDimensions::MATERIALIZATION_VERSION.to_s
        }
      )
    end
    sign_in users(:one)

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if %w[SCHEMA CACHE TRANSACTION].include?(payload[:name])
      next if payload[:cached]

      queries << payload[:sql]
    end
    get inbox_project_path(project, time_range: "all")
    ActiveSupport::Notifications.unsubscribe(subscriber)

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML.parse(response.body)
    expect(document.css("turbo-frame#project_inbox tr.inbox-row").size).to eq(100)
    expect(queries.size).to be <= 55
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end

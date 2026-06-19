# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorGroupJsonExporter do
  let(:owner) { create(:user) }
  let(:project) { create(:project, :ruby, user: owner, name: "Checkout") }
  let(:api_key) { create(:api_key, project: project, user: owner, name: "production") }
  let(:installation) { create(:github_installation, permissions: { "contents" => "read", "issues" => "write" }) }
  let(:github_repository) { create(:github_repository, github_installation: installation, full_name: "acme/storefront") }

  def grouped_error!(message:, release:, occurred_at:)
    event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      event_type: :error,
      level: "error",
      message: message,
      fingerprint: "checkout-nomethod",
      occurred_at: occurred_at,
      context: error_context(release: release)
    )
    ErrorGroupingService.call(event)
    event.reload
  end

  def error_context(release:)
    {
      "environment" => "production",
      "release" => release,
      "trace_id" => "trace-checkout",
      "request_id" => "req-checkout",
      "repository" => "acme/storefront",
      "exception" => {
        "class" => "NoMethodError",
        "message" => "undefined method total",
        "backtrace" => [ "app/models/order.rb:42:in `total'" ],
        "locals" => { "order_id" => "ord_123" }
      },
      "request" => {
        "path" => "/checkout",
        "headers" => { "User-Agent" => "RSpec" },
        "params" => { "controller" => "orders", "action" => "show" }
      }
    }
  end

  def build_group_with_context
    grouped_error!(message: "First checkout failure", release: "v1.2.3", occurred_at: 30.minutes.ago)
    latest_event = grouped_error!(message: "Latest checkout failure", release: "v1.2.4", occurred_at: 5.minutes.ago)
    group = latest_event.error_group
    source_repository = create(
      :project_source_repository,
      project: project,
      github_installation: installation,
      github_repository: github_repository,
      full_name: "acme/storefront",
      runtime_root: "/app"
    )
    create(
      :project_deployment,
      project: project,
      project_source_repository: source_repository,
      repository_full_name: "acme/storefront",
      release: "v1.2.3",
      commit_sha: "abcdef1",
      deployed_at: 40.minutes.ago,
      metadata: { "pull_request_number" => 12 }
    )
    create(
      :ingest_event,
      :log,
      project: project,
      api_key: api_key,
      message: "Checkout request started",
      occurred_at: 4.minutes.ago,
      context: { "trace_id" => "trace-checkout", "request_id" => "req-checkout", "environment" => "production" }
    )
    create(
      :error_group_external_link,
      project: project,
      error_group: group,
      created_by: owner,
      url: "https://github.com/acme/storefront/issues/12",
      metadata: { "source" => "spec" }
    )

    group.reload
  end

  def build_group_with_occurrences(count:)
    group = create(
      :error_group,
      project: project,
      fingerprint: "capped-export",
      title: "Capped export failure",
      first_seen_at: count.minutes.ago,
      last_seen_at: 1.minute.ago
    )
    events = count.times.map do |index|
      create(
        :ingest_event,
        project: project,
        api_key: api_key,
        event_type: :error,
        level: "error",
        message: "Occurrence #{index}",
        fingerprint: group.fingerprint,
        occurred_at: (count - index).minutes.ago,
        context: error_context(release: "v1.2.#{index}")
      )
    end
    events.each do |event|
      create(:error_occurrence, error_group: group, ingest_event: event, occurred_at: event.occurred_at)
    end

    group.update!(
      latest_event: events.max_by(&:occurred_at),
      first_seen_at: events.min_by(&:occurred_at).occurred_at,
      last_seen_at: events.max_by(&:occurred_at).occurred_at,
      occurrence_count: count
    )
    group.reload
  end

  it "exports a compact occurrence summary by default" do
    group = build_group_with_context

    payload = described_class.call(
      project: project,
      group: group,
      include_occurrences: false,
      generated_at: Time.zone.parse("2026-06-19 12:00:00"),
      logister_url: "https://logister.test/projects/#{project.uuid}/inbox?group_uuid=#{group.uuid}"
    )

    expect(payload.dig("export", "format")).to eq("logister_error_group")
    expect(payload.dig("export", "include_all_occurrences")).to be(false)
    expect(payload.dig("export", "include_occurrence_records")).to be(false)
    expect(payload.dig("error_group", "fingerprint")).to eq("checkout-nomethod")
    expect(payload.dig("latest_event", "message")).to eq("Latest checkout failure")
    expect(payload.dig("latest_event", "api_key", "name")).to eq("production")
    expect(payload.dig("exception", "application_frames").first).to include(
      "file" => "app/models/order.rb",
      "line_number" => 42
    )
    expect(payload.dig("request", "path")).to eq("/checkout")
    expect(payload.dig("occurrences", "mode")).to eq("summary")
    expect(payload.dig("occurrences", "stored_count")).to eq(2)
    expect(payload.fetch("occurrences")).not_to have_key("records")
    expect(payload.dig("related_logs", "count")).to eq(1)
    expect(payload.dig("source_repositories").first).to include(
      "full_name" => "acme/storefront",
      "configured" => true
    )
    expect(payload.dig("deployment_context", "matched")).to include(
      "release" => "v1.2.3",
      "commit_sha" => "abcdef1"
    )
    expect(payload.dig("external_links").first).to include(
      "url" => "https://github.com/acme/storefront/issues/12",
      "repository_full_name" => "acme/storefront"
    )
  end

  it "includes recent occurrence records and event payloads when requested" do
    group = build_group_with_context

    payload = described_class.call(
      project: project,
      group: group,
      include_occurrences: true,
      generated_at: Time.current,
      logister_url: nil
    )

    expect(payload.dig("export", "include_all_occurrences")).to be(false)
    expect(payload.dig("export", "include_occurrence_records")).to be(true)
    expect(payload.dig("export", "occurrence_record_limit")).to eq(50)
    expect(payload.dig("occurrences", "mode")).to eq("latest_records")
    expect(payload.dig("occurrences", "records").size).to eq(2)
    expect(payload.dig("occurrences", "record_limit")).to eq(50)
    expect(payload.dig("occurrences", "records_included")).to eq(2)
    expect(payload.dig("occurrences", "truncated")).to be(false)
    expect(payload.dig("occurrences", "records").map { |record| record.dig("ingest_event", "message") }).to contain_exactly(
      "First checkout failure",
      "Latest checkout failure"
    )
    expect(payload.dig("occurrences", "records").first.dig("ingest_event", "context", "exception", "class")).to eq("NoMethodError")
  end

  it "caps requested occurrence records to the latest 50" do
    group = build_group_with_occurrences(count: 55)

    payload = described_class.call(
      project: project,
      group: group,
      include_occurrences: true,
      generated_at: Time.current,
      logister_url: nil
    )

    occurrences = payload.fetch("occurrences")
    messages = occurrences.fetch("records").map { |record| record.dig("ingest_event", "message") }

    expect(occurrences).to include(
      "mode" => "latest_records",
      "stored_count" => 55,
      "record_limit" => 50,
      "records_included" => 50,
      "truncated" => true
    )
    expect(messages.first).to eq("Occurrence 54")
    expect(messages).to include("Occurrence 5")
    expect(messages).not_to include("Occurrence 0", "Occurrence 1", "Occurrence 2", "Occurrence 3", "Occurrence 4")
  end
end

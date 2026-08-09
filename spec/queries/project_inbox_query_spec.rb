# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectInboxQuery do
  let(:project) { create(:project, :android) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }

  def grouped_android_event(message:, release:, mechanism:, device:, fingerprint: nil, occurred_at: Time.current)
    context = JSON.parse(Rails.root.join("spec/fixtures/files/android_error_payload.json").read).fetch("context").deep_dup
    context["release"] = release
    context["app_version"], context["build_number"] = release.split("+")
    context["device_model"] = device
    context["error"] = { "mechanism" => mechanism, "handled" => mechanism == "handled_exception" }
    create(:ingest_event, project: project, api_key: api_key, message: message, fingerprint: fingerprint, context: context, occurred_at: occurred_at).tap do |event|
      ErrorGroupingService.call(event)
    end
  end

  describe "cache failure handling" do
    it "does not execute a failed database computation twice" do
      calls = 0

      expect do
        described_class.new(project: project).send(:cache_fetch, "failing-query", expires_in: 1.minute) do
          calls += 1
          raise "query failed"
        end
      end.to raise_error(RuntimeError, "query failed")

      expect(calls).to eq(1)
    end

    it "returns an already-computed value when the cache write fails" do
      cache = Class.new do
        def fetch(_key, **)
          yield
          raise "cache write failed"
        end
      end.new
      allow(Rails).to receive(:cache).and_return(cache)
      calls = 0

      value = described_class.new(project: project).send(:cache_fetch, "failed-write", expires_in: 1.minute) do
        calls += 1
        { ok: true }
      end

      expect(value).to eq(ok: true)
      expect(calls).to eq(1)
    end
  end

  it "sorts by the change in daily occurrence velocity" do
    hot = grouped_android_event(message: "Hot first", release: "3.0.0+30", mechanism: "handled_exception", device: "Pixel", fingerprint: "hot", occurred_at: Time.current)
    grouped_android_event(message: "Hot second", release: "3.0.0+30", mechanism: "handled_exception", device: "Pixel", fingerprint: "hot", occurred_at: Time.current - 1.hour)
    cold = grouped_android_event(message: "Cold", release: "2.0.0+20", mechanism: "handled_exception", device: "Pixel", fingerprint: "cold", occurred_at: Time.current - 36.hours)

    groups = described_class.new(project: project).groups(filter: "all", sort: "velocity")

    expect(groups.map(&:id)).to eq([ hot.error_group_id, cold.error_group_id ])
  end

  it "includes today in the displayed occurrence trend" do
    current = grouped_android_event(
      message: "Current failure",
      release: "3.0.0+30",
      mechanism: "handled_exception",
      device: "Pixel",
      occurred_at: Time.current
    )

    trend = described_class.new(project: project).group_trends([ current.error_group ], days: 7)

    expect(trend.fetch(current.error_group_id)).to eq([ 0, 0, 0, 0, 0, 0, 1 ])
  end

  it "keeps complete mobile event context for the shared web row presenter" do
    event = grouped_android_event(
      message: "Fatal checkout",
      release: "3.0.0+30",
      mechanism: "unhandled_exception",
      device: "Pixel 8"
    )
    query = described_class.new(project:)

    latest_event = query.latest_events([ event.error_group ]).fetch(event.error_group_id)
    row = ProjectInbox::RowPresenter.new(project:, group: event.error_group, event: latest_event)

    expect(latest_event.context.dig("exception", "stacktrace")).to be_present
    expect(row.failure_type_label).to eq("Fatal")
    expect(row.headline).to include("java.io.IOException", "CartStore.write")
    expect(row.supporting_label).to include("CartStore.kt:19", "3.0.0 (30)")
    expect(row.evidence_quality_label).to be_present
    expect(row.release_label).to eq("3.0.0 (30)")
    expect(row.cohort_label).to eq("Pixel 8 · Android 15 · API 35")
    expect(row.culprit).to include("CartStore.write", "CartStore.kt:19")

    cli_event = query.cli_latest_events([ event.error_group ]).fetch(event.id)
    expect(cli_event.context).to include("release" => "3.0.0+30")
    expect(cli_event.context).not_to have_key("exception")
  end

  it "uses a signed keyset cursor without repeating issues" do
    newest = grouped_android_event(message: "Newest", release: "3.0.0+30", mechanism: "handled_exception", device: "Pixel 9", fingerprint: "newest")
    older = grouped_android_event(message: "Older", release: "2.0.0+20", mechanism: "handled_exception", device: "Pixel 8", fingerprint: "older")
    newest.error_group.update!(last_seen_at: 1.hour.ago)
    older.error_group.update!(last_seen_at: 2.hours.ago)
    query = described_class.new(project: project, page_size: 1)

    first_page = query.page(filter: "all", sort: "last_seen")
    second_page = query.page(filter: "all", sort: "last_seen", cursor: first_page.next_cursor)

    expect(first_page.groups.map(&:id)).to eq([ newest.error_group_id ])
    expect(first_page.next_cursor).to be_present
    expect(second_page.groups.map(&:id)).to eq([ older.error_group_id ])
    expect(second_page.next_cursor).to be_nil
  end

  it "ignores a cursor when the filter context changes" do
    grouped_android_event(message: "One", release: "1.0.0+1", mechanism: "handled_exception", device: "Pixel", fingerprint: "one")
    grouped_android_event(message: "Two", release: "2.0.0+2", mechanism: "handled_exception", device: "Pixel", fingerprint: "two")
    query = described_class.new(project: project, page_size: 1)
    cursor = query.page(filter: "all", sort: "last_seen").next_cursor

    changed_context = query.page(filter: "all", dimensions: { release: "2.0.0+2" }, sort: "last_seen", cursor: cursor)

    expect(changed_context.groups.map(&:title)).to eq([ "Two" ])
  end

  it "combines Android release, device, API, and mechanism filters" do
    matching = grouped_android_event(message: "Fatal checkout", release: "2.0.0+50", mechanism: "unhandled_exception", device: "Pixel 8")
    grouped_android_event(message: "Handled checkout", release: "1.0.0+10", mechanism: "handled_exception", device: "Galaxy S24")

    groups = described_class.new(project: project).groups(
      filter: "unresolved",
      dimensions: {
        release: "2.0.0+50",
        mechanism: "unhandled_exception",
        device_model: "Pixel 8",
        api_level: "35"
      },
      sort: "recommended"
    )

    expect(groups.map(&:id)).to eq([ matching.error_group_id ])
  end

  it "separates profile dimensions in the query and cache contract" do
    grouped_android_event(message: "Build fifty", release: "2.0.0+50", mechanism: "handled_exception", device: "Pixel 8", fingerprint: "build-fifty")
    grouped_android_event(message: "Build ten", release: "1.0.0+10", mechanism: "handled_exception", device: "Pixel 8", fingerprint: "build-ten")
    query = described_class.new(project: project)

    expect(query.groups(filter: "all", dimensions: { release: "2.0.0+50" }).map(&:title)).to contain_exactly("Build fifty")
    expect(query.groups(filter: "all", dimensions: { release: "1.0.0+10" }).map(&:title)).to contain_exactly("Build ten")
  end

  it "uses one filtered occurrence scope for ranking, representative events, trends, and impact" do
    older_release = grouped_android_event(
      message: "Checkout failed in release one",
      release: "1.0.0+10",
      mechanism: "handled_exception",
      device: "Pixel 8",
      fingerprint: "shared-checkout",
      occurred_at: 2.hours.ago
    )
    grouped_android_event(
      message: "Checkout failed in release two",
      release: "2.0.0+20",
      mechanism: "unhandled_exception",
      device: "Pixel 9",
      fingerprint: "shared-checkout",
      occurred_at: Time.current
    )
    dimensions = { release: "1.0.0+10", device_model: "Pixel 8" }
    query = described_class.new(project: project)

    groups = query.groups(filter: "all", dimensions: dimensions, sort: "last_seen")
    representative = query.latest_events(groups, dimensions: dimensions).fetch(older_release.error_group_id)
    trends = query.group_trends(groups, days: 7, dimensions: dimensions)
    occurrence_scope = query.occurrence_relation(dimensions, group_ids: groups.map(&:id))
    impact = ErrorGroupImpactSummary.for_group(groups.first, since: nil, occurrence_scope: occurrence_scope)

    expect(groups.map(&:id)).to eq([ older_release.error_group_id ])
    expect(representative.id).to eq(older_release.id)
    expect(trends.fetch(older_release.error_group_id).sum).to eq(1)
    expect(impact.events).to eq(1)
    expect(impact.first_release).to eq("1.0.0+10")
    expect(impact.last_release).to eq("1.0.0+10")
    expect(impact.top_device).to eq(value: "Pixel 8", events: 1)
  end

  it "uses Apple diagnostic priority for the iOS recommended view" do
    ios_project = create(:project, :ios)
    ios_key = create(:api_key, project: ios_project, user: ios_project.user)
    base = JSON.parse(Rails.root.join("spec/fixtures/files/ios_error_payload.json").read).fetch("context")
    reported = create(:ingest_event, project: ios_project, api_key: ios_key, message: "Recent report", fingerprint: "reported", context: base, occurred_at: Time.current)
    watchdog_context = base.deep_dup
    watchdog_context["error"]["mechanism"] = "watchdog_termination"
    watchdog_context["diagnostic"]["kind"] = "watchdog_termination"
    watchdog = create(:ingest_event, project: ios_project, api_key: ios_key, message: "Older watchdog", fingerprint: "watchdog", context: watchdog_context, occurred_at: 1.hour.ago)
    ErrorGroupingService.call(reported)
    ErrorGroupingService.call(watchdog)

    groups = described_class.new(project: ios_project).groups(filter: "all")

    expect(groups.map(&:id)).to eq([ watchdog.error_group_id, reported.error_group_id ])
  end

  it "filters and searches materialized iOS source, channel, symbol, and platform fields" do
    ios_project = create(:project, :ios)
    ios_key = create(:api_key, project: ios_project, user: ios_project.user)
    matching_context = JSON.parse(Rails.root.join("spec/fixtures/files/ios_error_payload.json").read).fetch("context")
    matching_context["distribution"] = { "channel" => "testflight" }
    matching = create(:ingest_event, project: ios_project, api_key: ios_key, message: "Dynamic checkout failure", fingerprint: "ios-match", context: matching_context)
    other_context = matching_context.deep_dup
    other_context["diagnostic"]["source"] = "metrickit"
    other_context["distribution"]["channel"] = "app_store"
    other = create(:ingest_event, project: ios_project, api_key: ios_key, message: "Other failure", fingerprint: "ios-other", context: other_context)
    ErrorGroupingService.call(matching)
    ErrorGroupingService.call(other)
    query = described_class.new(project: ios_project)

    expect(query.groups(
      filter: "all",
      query: "CheckoutViewModel.submit",
      dimensions: { diagnostic_source: "sdk", distribution_channel: "testflight", apple_platform: "ios" }
    ).map(&:id)).to eq([ matching.error_group_id ])
  end
end

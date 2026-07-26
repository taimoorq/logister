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

  it "sorts by the change in daily occurrence velocity" do
    hot = grouped_android_event(message: "Hot first", release: "3.0.0+30", mechanism: "handled_exception", device: "Pixel", fingerprint: "hot", occurred_at: Time.current)
    grouped_android_event(message: "Hot second", release: "3.0.0+30", mechanism: "handled_exception", device: "Pixel", fingerprint: "hot", occurred_at: Time.current - 1.hour)
    cold = grouped_android_event(message: "Cold", release: "2.0.0+20", mechanism: "handled_exception", device: "Pixel", fingerprint: "cold", occurred_at: Time.current - 36.hours)

    groups = described_class.new(project: project).groups(filter: "all", sort: "velocity")

    expect(groups.map(&:id)).to eq([ hot.error_group_id, cold.error_group_id ])
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
end

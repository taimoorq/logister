# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectInbox::EvidenceSignalQuery do
  let(:now) { Time.zone.parse("2026-08-09 12:00:00") }
  let(:project) { create(:project, :android) }
  let(:api_key) { create(:api_key, project:, user: project.user) }

  def insert_occurrences(group, times:, precision: "exact", installations: [], sessions: [], session_ages: [])
    rows = times.each_with_index.map do |occurred_at, index|
      event = create(:ingest_event, project:, api_key:, occurred_at:)
      {
        uuid: SecureRandom.uuid,
        error_group_id: group.id,
        ingest_event_id: event.id,
        occurred_at:,
        ingest_event_occurred_at: occurred_at,
        installation_hash: installations[index],
        session_hash: sessions[index],
        dimensions: {
          "time_precision" => precision,
          "session_age_ms" => session_ages[index]&.to_s
        }.compact,
        created_at: now,
        updated_at: now
      }
    end
    ErrorOccurrence.insert_all!(rows)
  end

  def query(*groups)
    scope = ErrorOccurrence.joins(:error_group).where(error_groups: { project_id: project.id })
    described_class.call(occurrence_scope: scope, group_ids: groups.map(&:id), now:)
  end

  def insert_cost_interval(group, start_at:, end_at:, values:, measurement: "total_cpu_time", unit: "seconds")
    rows = values.map.with_index do |value, index|
      occurred_at = end_at - index.seconds
      event = create(:ingest_event, project:, api_key:, occurred_at:)
      {
        uuid: SecureRandom.uuid,
        error_group_id: group.id,
        ingest_event_id: event.id,
        occurred_at:,
        ingest_event_occurred_at: occurred_at,
        dimensions: {
          "time_precision" => "reporting_interval",
          "diagnostic_measurement" => measurement,
          "diagnostic_measurement_value" => value.to_s,
          "diagnostic_measurement_unit" => unit,
          "reporting_start_at" => start_at.utc.iso8601,
          "reporting_end_at" => end_at.utc.iso8601
        },
        created_at: now,
        updated_at: now
      }
    end
    ErrorOccurrence.insert_all!(rows)
  end

  it "requires exact clocks, minimum comparison volume, delta, and a two-times increase for Spiking" do
    group = create(:error_group, project:)
    insert_occurrences(group, times: Array.new(5) { now - 30.hours } + Array.new(10) { now - 2.hours })
    insert_occurrences(group, times: [ now - 1.hour ], precision: "reporting_interval")

    signal = query(group).fetch(group.id)

    expect(signal).to have_attributes(key: :spiking, label: "Spiking", concise_label: "+100% in 24h")
    expect(signal.evidence).to include(
      "time_precision" => "exact",
      "current_events" => 10,
      "previous_events" => 5,
      "minimum_current_events" => 10,
      "minimum_previous_events" => 5
    )
  end

  it "uses repetitive installation impact only when identity coverage is sufficient" do
    repetitive = create(:error_group, project:)
    insufficient = create(:error_group, project:)
    times = Array.new(12) { |index| now - (index + 1).hours }
    insert_occurrences(
      repetitive,
      times:,
      installations: Array.new(12) { |index| "installation-#{index % 3}" }
    )
    insert_occurrences(
      insufficient,
      times:,
      installations: Array.new(9) { |index| "installation-#{index % 3}" }
    )

    signals = query(repetitive, insufficient)

    expect(signals.fetch(repetitive.id)).to have_attributes(
      key: :repetitive,
      label: "Repetitive",
      concise_label: "4.0 events/installation"
    )
    expect(signals.fetch(repetitive.id).evidence).to include(
      "identity_kind" => "installation",
      "identified_events" => 12,
      "distinct_identities" => 3,
      "identity_coverage" => 1.0
    )
    expect(signals).not_to have_key(insufficient.id)
  end

  it "does not label low-volume increases" do
    group = create(:error_group, project:)
    insert_occurrences(group, times: Array.new(2) { now - 30.hours } + Array.new(8) { now - 2.hours })

    expect(query(group)).to be_empty
  end

  it "assigns Early session only with exact valid timing and sufficient coverage" do
    group = create(:error_group, project:)
    times = Array.new(10) { |index| now - (index + 1).hours }
    insert_occurrences(group, times:, session_ages: [ 500, 1_000, 2_000, 3_000, 4_000, 4_500, 10_000, 20_000, 30_000, nil ])

    signal = query(group).fetch(group.id)

    expect(signal).to have_attributes(
      key: :early_session,
      label: "Early session",
      concise_label: "67% in first 5s"
    )
    expect(signal.evidence).to include(
      "threshold_ms" => 5_000,
      "timed_events" => 9,
      "early_events" => 6,
      "total_events" => 10,
      "timing_coverage" => 0.9
    )
  end

  it "compares diagnostic cost only across adjacent equal reporting intervals with matching units and volume" do
    group = create(:error_group, project:)
    prior_start = now - 2.days
    current_start = now - 1.day
    insert_cost_interval(group, start_at: prior_start, end_at: current_start, values: [ 10, 10, 10, 10, 10 ])
    insert_cost_interval(group, start_at: current_start, end_at: now, values: [ 25, 25, 25, 25, 25 ])

    signal = query(group).fetch(group.id)

    expect(signal).to have_attributes(
      key: :diagnostic_cost,
      label: "Cost increased",
      concise_label: "2.5× CPU time"
    )
    expect(signal.evidence).to include(
      "time_precision" => "reporting_interval",
      "measurement" => "total_cpu_time",
      "unit" => "seconds",
      "current_events" => 5,
      "previous_events" => 5,
      "current_total" => 125.0,
      "previous_total" => 50.0,
      "ratio" => 2.5
    )
  end

  it "does not compare overlapping, different-unit, or under-sampled diagnostic intervals" do
    overlapping = create(:error_group, project:)
    different_units = create(:error_group, project:)
    under_sampled = create(:error_group, project:)
    insert_cost_interval(overlapping, start_at: now - 2.days, end_at: now - 12.hours, values: Array.new(5, 10))
    insert_cost_interval(overlapping, start_at: now - 1.day, end_at: now, values: Array.new(5, 30))
    insert_cost_interval(different_units, start_at: now - 2.days, end_at: now - 1.day, values: Array.new(5, 10), unit: "seconds")
    insert_cost_interval(different_units, start_at: now - 1.day, end_at: now, values: Array.new(5, 30), unit: "milliseconds")
    insert_cost_interval(under_sampled, start_at: now - 2.days, end_at: now - 1.day, values: Array.new(4, 10))
    insert_cost_interval(under_sampled, start_at: now - 1.day, end_at: now, values: Array.new(4, 30))

    expect(query(overlapping, different_units, under_sampled)).to be_empty
  end
end

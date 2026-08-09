# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::PostgresRetentionCoverage do
  let(:now) { Time.utc(2026, 8, 9, 12) }
  let(:repository) { instance_double(described_class::Repository) }

  def policy(project_id:, hot_days: 30, trace_days: 30, error_days: nil)
    described_class::Policy.new(project_id, hot_days, trace_days, error_days)
  end

  def coverage(project_ids: [ 1 ], signals: [ "metric" ], from: now - 29.days, to: now)
    described_class.call(project_ids:, signals:, from:, to:, repository:, now:)
  end

  it "marks an ordinary-event range inside hot retention as complete" do
    allow(repository).to receive(:policies_for).and_return([ policy(project_id: 1, hot_days: 30) ])

    result = coverage

    expect(result).to be_complete
    expect(result.to_h).to eq(
      complete: true,
      reason: "within_postgres_retention",
      requested_from: (now - 29.days).iso8601,
      requested_to: now.iso8601,
      retained_from: (now - 30.days).iso8601
    )
  end

  it "marks an ordinary-event range older than hot retention as incomplete" do
    allow(repository).to receive(:policies_for).and_return([ policy(project_id: 1, hot_days: 30) ])

    result = coverage(from: now - 31.days)

    expect(result).not_to be_complete
    expect(result.reason).to eq("postgres_retention_window")
    expect(result.retained_from).to eq(now - 30.days)
  end

  it "uses trace retention for spans" do
    allow(repository).to receive(:policies_for).and_return([ policy(project_id: 1, hot_days: 7, trace_days: 90) ])

    result = coverage(signals: [ "span" ], from: now - 60.days)

    expect(result).to be_complete
    expect(result.retained_from).to eq(now - 90.days)
  end

  it "treats errors with nil error retention as retained forever" do
    allow(repository).to receive(:policies_for).and_return([ policy(project_id: 1, error_days: nil) ])

    result = coverage(signals: [ "error" ], from: now - 10.years)

    expect(result).to be_complete
    expect(result.retained_from).to be_nil
  end

  it "uses finite error retention when it is configured" do
    allow(repository).to receive(:policies_for).and_return([ policy(project_id: 1, error_days: 180) ])

    result = coverage(signals: [ "error" ], from: now - 181.days)

    expect(result).not_to be_complete
    expect(result.retained_from).to eq(now - 180.days)
  end

  it "uses the shortest configured window across every requested project and signal" do
    allow(repository).to receive(:policies_for).and_return(
      [
        policy(project_id: 1, hot_days: 90, trace_days: 60, error_days: nil),
        policy(project_id: 2, hot_days: 7, trace_days: 30, error_days: 180)
      ]
    )

    result = coverage(
      project_ids: [ 2, 1 ],
      signals: %w[error metric span],
      from: now - 10.days
    )

    expect(result).not_to be_complete
    expect(result.retained_from).to eq(now - 7.days)
    expect(repository).to have_received(:policies_for).with(project_ids: [ 1, 2 ])
  end

  it "fails closed for unknown projects and unsupported signals" do
    allow(repository).to receive(:policies_for).and_return([])

    missing_project = coverage
    unsupported_signal = coverage(signals: [ "profile" ])

    expect(missing_project).not_to be_complete
    expect(missing_project.reason).to eq("missing_projects")
    expect(unsupported_signal).not_to be_complete
    expect(unsupported_signal.reason).to eq("unsupported_signals")
  end

  it "uses model defaults without creating a retention policy" do
    project = create(:project)

    expect do
      result = described_class.call(
        project_ids: [ project.id ],
        signals: [ "metric" ],
        from: now - 29.days,
        to: now,
        now:
      )

      expect(result).to be_complete
      expect(result.retained_from).to eq(now - ProjectRetentionPolicy::DEFAULT_HOT_RETENTION_DAYS.days)
    end.not_to change(ProjectRetentionPolicy, :count)
  end
end

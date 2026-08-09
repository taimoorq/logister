# frozen_string_literal: true

require "rails_helper"

RSpec.describe FrequentErrorNotificationEvaluationJob, type: :job do
  it "coalesces a noisy group to one scheduled evaluation per hour bucket" do
    now = Time.zone.parse("2026-08-08 12:20:00 UTC")
    group = create(:error_group)

    first = NotificationEvaluation.enqueue_frequent_error!(error_group: group, occurred_at: now)
    second = NotificationEvaluation.enqueue_frequent_error!(error_group: group, occurred_at: now + 10.minutes)

    expect(second).to eq(first)
    expect(NotificationEvaluation.where(error_group: group, kind: "frequent_error").count).to eq(1)
    expect(FrequentErrorNotificationEvaluationJob).to have_been_enqueued.exactly(:once)
    expect(first.reload.observation_count).to eq(2)
  end

  it "marks a claimed evaluation complete after dispatch" do
    now = Time.zone.parse("2026-08-08 12:20:00 UTC")
    group = create(:error_group)
    evaluation = NotificationEvaluation.create!(
      project: group.project,
      error_group: group,
      kind: "frequent_error",
      bucket: "2026080812",
      available_at: now,
      status: "pending",
      observation_count: 1
    )
    allow(ProjectEmailNotificationDispatcher).to receive(:call).and_return([])

    described_class.perform_now(evaluation.id, now.iso8601)

    expect(evaluation.reload.status).to eq("completed")
    expect(evaluation.attempts).to eq(1)
  end

  it "reopens a completed hourly evaluation when a later occurrence arrives" do
    now = Time.zone.parse("2026-08-08 12:20:00 UTC")
    group = create(:error_group)
    evaluation = NotificationEvaluation.create!(
      project: group.project,
      error_group: group,
      kind: "frequent_error",
      bucket: "2026080812",
      available_at: now,
      status: "completed",
      observation_count: 3,
      processing_observation_count: 3,
      completed_at: now
    )

    expect {
      NotificationEvaluation.enqueue_frequent_error!(error_group: group, occurred_at: now + 10.minutes)
    }.to have_enqueued_job(described_class).with(evaluation.id)

    expect(evaluation.reload).to have_attributes(
      status: "pending",
      observation_count: 4,
      completed_at: nil
    )
  end

  it "schedules another pass when an occurrence arrives while evaluation is processing" do
    now = Time.zone.parse("2026-08-08 12:20:00 UTC")
    group = create(:error_group)
    evaluation = NotificationEvaluation.create!(
      project: group.project,
      error_group: group,
      kind: "frequent_error",
      bucket: "2026080812",
      available_at: now,
      status: "pending",
      observation_count: 1
    )
    allow(ProjectEmailNotificationDispatcher).to receive(:call) do
      NotificationEvaluation.enqueue_frequent_error!(
        error_group: group,
        occurred_at: now + 1.minute
      )
      []
    end

    expect {
      described_class.perform_now(evaluation.id, now.iso8601)
    }.to have_enqueued_job(described_class).with(evaluation.id, kind_of(String))

    expect(evaluation.reload.status).to eq("pending")
    expect(evaluation.observation_count).to eq(2)
  end
end

# frozen_string_literal: true

class ClickhouseCoverageSealerJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :analytics
  sidekiq_recurring_schedule(
    key: "clickhouse_coverage_sealer",
    every: 1.hour,
    schedule_ttl: 2.hours
  )

  PROJECT_BATCH_SIZE = 10

  def perform(after_project_id = 0, closed_before = Time.current.beginning_of_hour.iso8601)
    closed_at = Time.zone.parse(closed_before.to_s).utc.beginning_of_hour
    project_ids = active_project_ids(closed_at, after_project_id.to_i)
    return if project_ids.empty?

    client = Logister::ClickhouseClient.new
    project_ids.each do |project_id|
      Logister::ClickhouseRecentCoverageSealer.call(
        project_id: project_id,
        client: client,
        closed_before: closed_at
      )
    rescue StandardError => error
      Rails.logger.warn(
        "clickhouse_coverage_sealer_error project_id=#{project_id} " \
        "error=#{error.class}: #{error.message}"
      )
    end
    self.class.perform_later(project_ids.last, closed_before) if project_ids.length == PROJECT_BATCH_SIZE
  ensure
    close_client(client)
    reschedule_sidekiq_recurring_job if after_project_id.to_i.zero?
  end

  private

  def active_project_ids(closed_at, after_project_id)
    activity_window = (closed_at - Logister::ClickhouseRecentCoverageSealer::DEFAULT_LOOKBACK)...closed_at
    active_project_scope = { projects: { purge_requested_at: nil } }
    ids = IngestEvent.joins(:project)
      .where(active_project_scope)
      .where(occurred_at: activity_window)
      .where("ingest_events.project_id > ?", after_project_id)
      .distinct.order(:project_id).limit(PROJECT_BATCH_SIZE).pluck(:project_id)
    ids.concat(
      TraceSpan.joins(:project)
        .where(active_project_scope)
        .where(started_at: activity_window)
        .where("trace_spans.project_id > ?", after_project_id)
        .distinct.order(:project_id).limit(PROJECT_BATCH_SIZE).pluck(:project_id)
    )
    ids.concat(
      TelemetryOutboxEvent.joins(:project)
        .where(active_project_scope)
        .where(recorded_at: activity_window)
        .where("telemetry_outbox_events.project_id > ?", after_project_id)
        .distinct.order(:project_id).limit(PROJECT_BATCH_SIZE).pluck(:project_id)
    )
    ids.concat(
      TelemetryProjectionWatermark.where(bucket_start_at: activity_window)
        .joins(:project)
        .where(active_project_scope)
        .where("accepted_count > 0 OR delivered_count > 0")
        .where("telemetry_projection_watermarks.project_id > ?", after_project_id)
        .distinct
        .order(:project_id)
        .limit(PROJECT_BATCH_SIZE)
        .pluck(:project_id)
    )
    ids.map(&:to_i).uniq.sort.first(PROJECT_BATCH_SIZE)
  end

  def close_client(client)
    client&.close
  rescue StandardError => error
    Rails.logger.warn("clickhouse_coverage_sealer_close_error error=#{error.class}: #{error.message}")
  end
end

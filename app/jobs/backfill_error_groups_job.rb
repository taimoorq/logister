# One-shot backfill: run this once after deploying the ErrorGroup migration.
#
#   bin/rails runner "BackfillErrorGroupsJob.perform_now"
#   — or via the queue —
#   BackfillErrorGroupsJob.perform_later
#
class BackfillErrorGroupsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 200

  def perform
    # Process only error-type events that haven't been grouped yet,
    # oldest first so first_seen_at is correct.
    scope = IngestEvent
      .where(event_type: :error)
      .where(error_group_id: nil)
      .order(:occurred_at)

    total   = scope.count
    grouped = 0

    Rails.logger.info "[BackfillErrorGroupsJob] #{total} ungrouped error events to process"

    scope.find_each(batch_size: BATCH_SIZE) do |event|
      ErrorGroupingService.call(event)
      grouped += 1
      Rails.logger.info "[BackfillErrorGroupsJob] #{grouped}/#{total}" if (grouped % 100).zero?
    rescue => e
      Rails.logger.error "[BackfillErrorGroupsJob] Failed on event #{event.uuid}: #{e.message}"
    end

    Rails.logger.info "[BackfillErrorGroupsJob] Done — #{grouped} events grouped"
  end
end

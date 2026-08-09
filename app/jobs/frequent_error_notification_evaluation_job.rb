class FrequentErrorNotificationEvaluationJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound
  retry_on StandardError, wait: :polynomially_longer, attempts: 8

  def perform(evaluation_id, now_iso8601 = Time.current.iso8601)
    evaluation = NotificationEvaluation.includes(error_group: :project).find(evaluation_id)
    now = Time.zone.parse(now_iso8601.to_s)
    unless evaluation.claim!(now: now)
      if evaluation.status == "pending" && evaluation.available_at > now
        self.class.set(wait_until: evaluation.available_at).perform_later(evaluation.id, evaluation.available_at.iso8601)
      end
      return
    end

    group = evaluation.error_group
    ProjectEmailNotificationDispatcher.call(
      project: group.project,
      kind: "frequent_error",
      error_group: group,
      metadata: { "bucket" => evaluation.bucket, "evaluated_at" => now.utc.iso8601 },
      bucket: evaluation.bucket,
      now: now
    )
    requeue = evaluation.complete!(now: now)
    if requeue
      self.class.set(wait_until: evaluation.available_at).perform_later(evaluation.id, evaluation.available_at.iso8601)
    end
  rescue StandardError => error
    evaluation&.release!(error, now: now || Time.current) if evaluation&.persisted?
    raise
  end
end

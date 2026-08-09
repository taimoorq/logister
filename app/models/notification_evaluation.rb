class NotificationEvaluation < ApplicationRecord
  KINDS = %w[frequent_error].freeze
  STATUSES = %w[pending processing completed].freeze
  PROCESSING_LEASE = 10.minutes
  COALESCE_WINDOW = 5.seconds

  belongs_to :project
  belongs_to :error_group

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :bucket, :available_at, presence: true
  validates :attempts, :observation_count, :processing_observation_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ready, ->(now = Time.current) {
    where(status: "pending").where("available_at <= ?", now)
      .or(where(status: "processing").where("started_at <= ?", now - PROCESSING_LEASE))
  }

  def self.enqueue_frequent_error!(error_group:, occurred_at:)
    evaluation, schedule = observe_frequent_error!(error_group: error_group, occurred_at: occurred_at)
    schedule_frequent_error!(evaluation) if schedule
    evaluation
  end

  # Persistence is separate from Sidekiq acceleration so callers can commit an
  # observation atomically with the error-group mutation that caused it.
  def self.observe_frequent_error!(error_group:, occurred_at:)
    bucket = occurred_at.utc.strftime("%Y%m%d%H")
    evaluation = create_or_find_by!(kind: "frequent_error", error_group: error_group, bucket: bucket) do |record|
      record.project = error_group.project
      record.status = "pending"
      record.available_at = Time.current + COALESCE_WINDOW
    end
    created = evaluation.previously_new_record?
    schedule = false
    now = Time.current
    evaluation.with_lock do
      schedule = created || evaluation.status == "completed"
      evaluation.status = "pending" if evaluation.status == "completed"
      evaluation.completed_at = nil if evaluation.status == "pending"
      evaluation.observation_count += 1
      evaluation.last_observed_at = now
      evaluation.available_at = now + COALESCE_WINDOW if evaluation.status == "pending"
      evaluation.save!
    end

    [ evaluation, schedule ]
  end

  def self.schedule_frequent_error!(evaluation)
    job = FrequentErrorNotificationEvaluationJob
      .set(wait_until: evaluation.available_at)
      .perform_later(evaluation.id)
    return job if job && (!job.respond_to?(:successfully_enqueued?) || job.successfully_enqueued?)

    raise ActiveJob::EnqueueError, "notification evaluation #{evaluation.id} was not enqueued"
  end

  def claim!(now: Time.current)
    with_lock do
      return false if status == "completed"
      return false if status == "pending" && available_at > now
      return false if status == "processing" && started_at.present? && started_at > now - PROCESSING_LEASE

      update!(
        status: "processing",
        started_at: now,
        attempts: attempts + 1,
        processing_observation_count: observation_count,
        last_error: nil
      )
      true
    end
  end

  def complete!(now: Time.current)
    requeue = false
    with_lock do
      if observation_count > processing_observation_count
        update!(
          status: "pending",
          started_at: nil,
          completed_at: nil,
          available_at: now + COALESCE_WINDOW,
          last_error: nil
        )
        requeue = true
      else
        update!(status: "completed", completed_at: now, started_at: nil, last_error: nil)
      end
    end
    requeue
  end

  def release!(error, now: Time.current)
    delay = [ 2**[ attempts, 8 ].min, 300 ].min.seconds
    update!(
      status: "pending",
      started_at: nil,
      available_at: now + delay,
      last_error: "#{error.class}: #{error.message}".truncate(2_000)
    )
  end
end

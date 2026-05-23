class ApplicationJob < ActiveJob::Base
  if Rails.env.development?
    require "bullet/active_job"
    include Bullet::ActiveJob
  end

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end

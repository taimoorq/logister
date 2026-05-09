redis_url = ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  config.on(:startup) do
    ProjectErrorDigestSchedulerJob.ensure_scheduled! if Rails.env.production?
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

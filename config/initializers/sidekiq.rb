redis_url = InstanceConfiguration.redis_url(:sidekiq)

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  config.on(:startup) do
    if Rails.env.production?
      Logister::SidekiqRecurringScheduler.install!
      Logister::WorkerPoolHeartbeat.record!(concurrency: config.concurrency)
    end
  end

  config.on(:beat) do
    if Rails.env.production?
      Logister::WorkerPoolHeartbeat.record!(concurrency: config.concurrency)
      Logister::SidekiqRecurringScheduler.reconcile!
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

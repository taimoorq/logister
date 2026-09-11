require_relative "../../lib/logister/sidekiq_workload_configuration"

redis_url = InstanceConfiguration.redis_url(:sidekiq)

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
  Logister::SidekiqWorkloadConfiguration.apply!(config)

  config.on(:startup) do
    if Rails.env.production?
      Logister::SidekiqRecurringScheduler.install!
      Logister::WorkerPoolHeartbeat.record!(concurrency: config.total_concurrency)
    end
  end

  config.on(:beat) do
    if Rails.env.production?
      Logister::WorkerPoolHeartbeat.record!(concurrency: config.total_concurrency)
      Logister::SidekiqRecurringScheduler.reconcile!
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

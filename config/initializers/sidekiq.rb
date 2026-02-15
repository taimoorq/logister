redis_url = ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")
redis_namespace = ENV.fetch("REDIS_NAMESPACE", "logister:#{Rails.env}")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url, namespace: redis_namespace }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url, namespace: redis_namespace }
end

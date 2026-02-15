RailsCloudflareTurnstile.configure do |config|
  site_key = ENV["LOGISTER_TURNSTILE_SITE_KEY"]
  secret_key = ENV["LOGISTER_TURNSTILE_SECRET_KEY"]
  enabled = ActiveModel::Type::Boolean.new.cast(ENV.fetch("LOGISTER_TURNSTILE_ENABLED", Rails.env.production?.to_s))

  config.site_key = site_key
  config.secret_key = secret_key
  config.enabled = enabled && site_key.present? && secret_key.present?
  config.fail_open = false
  config.timeout = 3.0
end

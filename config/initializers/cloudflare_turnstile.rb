RailsCloudflareTurnstile.configure do |config|
  site_key = InstanceConfiguration.value("authentication.turnstile_site_key")
  secret_key = InstanceConfiguration.value("authentication.turnstile_secret_key")
  enabled = InstanceConfiguration.value("authentication.turnstile_enabled")

  config.site_key = site_key
  config.secret_key = secret_key
  config.enabled = enabled && site_key.present? && secret_key.present?
  config.fail_open = false
  config.timeout = 3.0
end

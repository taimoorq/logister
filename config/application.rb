require_relative "boot"

require "rails/all"
require_relative "../app/middleware/client_submissions/pre_auth_ip_guard"
require_relative "../app/middleware/client_submissions/single_event_body_limiter"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Logister
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Tailwind CSS build output (must be in application.rb so Propshaft sees it at boot)
    config.assets.paths << Rails.root.join("app/assets/builds")

    # PostgreSQL partitioning and advanced indexes are represented more reliably in structure.sql.
    config.active_record.schema_format = :sql

    # Protect telemetry intake before Rails parses JSON or performs credential lookups.
    # RemoteIp stays ahead of the guard so proxy-aware source identities remain accurate.
    config.middleware.insert_after ActionDispatch::RemoteIp, ClientSubmissions::PreAuthIpGuard
    config.middleware.insert_after ClientSubmissions::PreAuthIpGuard, ClientSubmissions::SingleEventBodyLimiter

    # Generate RSpec specs instead of Minitest tests
    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement nil
    end
  end
end

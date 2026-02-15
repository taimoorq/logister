require "rails/railtie"

module Logister
  class Railtie < Rails::Railtie
    config.logister = ActiveSupport::OrderedOptions.new

    initializer "logister.configure" do |app|
      Logister.configure do |config|
        config.api_key = app.config.logister.api_key if app.config.logister.api_key
        config.endpoint = app.config.logister.endpoint if app.config.logister.endpoint
        config.environment = app.config.logister.environment if app.config.logister.environment
        config.service = app.config.logister.service if app.config.logister.service
        config.release = app.config.logister.release if app.config.logister.release
      end
    end

    initializer "logister.middleware" do |app|
      app.middleware.use Logister::Middleware
    end
  end
end

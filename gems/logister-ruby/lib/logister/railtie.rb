require 'rails/railtie'
require_relative 'active_job_reporter'

module Logister
  class Railtie < Rails::Railtie
    config.logister = ActiveSupport::OrderedOptions.new

    initializer 'logister.configure' do |app|
      Logister.configure do |config|
        copy_setting(app, config, :api_key)
        copy_setting(app, config, :endpoint)
        copy_setting(app, config, :environment)
        copy_setting(app, config, :service)
        copy_setting(app, config, :release)
        copy_setting(app, config, :enabled)
        copy_setting(app, config, :timeout_seconds)
        copy_setting(app, config, :ignore_exceptions)
        copy_setting(app, config, :ignore_environments)
        copy_setting(app, config, :ignore_paths)
        copy_setting(app, config, :before_notify)
        copy_setting(app, config, :async)
        copy_setting(app, config, :queue_size)
        copy_setting(app, config, :max_retries)
        copy_setting(app, config, :retry_base_interval)
        copy_setting(app, config, :capture_db_metrics)
        copy_setting(app, config, :db_metric_min_duration_ms)
        copy_setting(app, config, :db_metric_sample_rate)
        copy_setting(app, config, :feature_flags_resolver)
        copy_setting(app, config, :dependency_resolver)
        copy_setting(app, config, :anonymize_ip)
        copy_setting(app, config, :max_breadcrumbs)
        copy_setting(app, config, :max_dependencies)
        copy_setting(app, config, :capture_sql_breadcrumbs)
        copy_setting(app, config, :sql_breadcrumb_min_duration_ms)
      end
    end

    initializer 'logister.middleware' do |app|
      app.middleware.use Logister::Middleware
    end

    initializer 'logister.sql_subscriber' do
      Logister::SqlSubscriber.install!
    end

    initializer "logister.request_subscriber" do
      Logister::RequestSubscriber.install!
    end

    initializer "logister.active_job_reporter" do
      ActiveSupport.on_load(:active_job) do
        Logister::ActiveJobReporter.install!
      end
    end

    private

    def copy_setting(app, config, key)
      value = app.config.logister.send(key)
      return if value.nil?

      config.send("#{key}=", value)
    end
  end
end

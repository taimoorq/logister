require 'logger'

module Logister
  class Configuration
    attr_accessor :api_key, :endpoint, :environment, :service, :release, :enabled, :timeout_seconds, :logger,
                  :ignore_exceptions, :ignore_environments, :ignore_paths, :before_notify,
                  :async, :queue_size, :max_retries, :retry_base_interval,
                  :capture_db_metrics, :db_metric_min_duration_ms, :db_metric_sample_rate,
                  :feature_flags_resolver, :dependency_resolver, :anonymize_ip,
                  :max_breadcrumbs, :max_dependencies,
                  :capture_sql_breadcrumbs, :sql_breadcrumb_min_duration_ms

    def initialize
      @api_key = ENV['LOGISTER_API_KEY']
      @endpoint = ENV.fetch('LOGISTER_ENDPOINT', 'https://logister.org/api/v1/ingest_events')
      @environment = ENV.fetch('RAILS_ENV', ENV.fetch('RACK_ENV', 'development'))
      @service = ENV.fetch('LOGISTER_SERVICE', 'ruby-app')
      @release = ENV['LOGISTER_RELEASE']
      @enabled = true
      @timeout_seconds = 2
      @logger = Logger.new($stdout)
      @logger.level = Logger::WARN

      @ignore_exceptions = []
      @ignore_environments = []
      @ignore_paths = []
      @before_notify = nil

      @async = true
      @queue_size = 1000
      @max_retries = 3
      @retry_base_interval = 0.5

      @capture_db_metrics = false
      @db_metric_min_duration_ms = 0.0
      @db_metric_sample_rate = 1.0

      @feature_flags_resolver = nil
      @dependency_resolver = nil
      @anonymize_ip = false
      @max_breadcrumbs = 40
      @max_dependencies = 20
      @capture_sql_breadcrumbs = true
      @sql_breadcrumb_min_duration_ms = 25.0
    end
  end
end

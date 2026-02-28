require_relative 'logister/version'
require_relative 'logister/configuration'
require_relative 'logister/client'
require_relative 'logister/reporter'
require_relative 'logister/context_helpers'
require_relative 'logister/context_store'
require_relative 'logister/middleware'
require_relative 'logister/sql_subscriber'
require_relative 'logister/request_subscriber'

module Logister
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      @reporter = nil
    end

    def reporter
      @reporter ||= Reporter.new(configuration)
    end

    def report_error(exception, **kwargs)
      reporter.report_error(exception, **kwargs)
    end

    def report_metric(**kwargs)
      reporter.report_metric(**kwargs)
    end

    def flush(timeout: 2)
      reporter.flush(timeout: timeout)
    end

    def shutdown
      reporter.shutdown
    end

    def add_breadcrumb(category:, message:, data: {}, level: "info")
      ContextStore.add_manual_breadcrumb(
        category: category,
        message: message,
        data: data,
        level: level
      )
    end

    def add_dependency(name:, host: nil, method: nil, status: nil, duration_ms: nil, kind: nil, data: {})
      ContextStore.add_manual_dependency(
        name: name,
        host: host,
        method: method,
        status: status,
        duration_ms: duration_ms,
        kind: kind,
        data: data
      )
    end
  end
end

require_relative 'logister/railtie' if defined?(Rails::Railtie)

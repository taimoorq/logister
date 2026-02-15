require_relative "logister/version"
require_relative "logister/configuration"
require_relative "logister/client"
require_relative "logister/reporter"
require_relative "logister/middleware"

module Logister
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
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
  end
end

require_relative "logister/railtie" if defined?(Rails::Railtie)

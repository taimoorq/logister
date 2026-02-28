require "test_helper"
require Rails.root.join("gems/logister-ruby/lib/logister")

class LogisterActiveJobReporterTest < ActiveSupport::TestCase
  class ExplodingJob < ActiveJob::Base
    queue_as :default

    def perform(payload)
      Logister.add_dependency(name: "redis.get", kind: "redis", duration_ms: 4.2)
      raise ArgumentError, "job boom #{payload["order_id"]}"
    end
  end

  test "reports failed jobs with job context and filtered args" do
    Logister::ActiveJobReporter.install!

    captured = nil
    had_report_error = Logister.respond_to?(:report_error)
    original_report_error = Logister.method(:report_error) if had_report_error

    Logister.define_singleton_method(:report_error) do |error, context:|
      captured = { error: error, context: context }
      true
    end

    assert_raises(ArgumentError) do
      ExplodingJob.perform_now({ "order_id" => 123, "email" => "one@example.com", "token" => "secret-token" })
    end

    assert captured
    assert_kind_of ArgumentError, captured[:error]
    assert_equal ExplodingJob.name, captured.dig(:context, :job, :jobClass)
    assert_equal "default", captured.dig(:context, :job, :queue)
    assert_equal "[FILTERED]", captured.dig(:context, :job, :arguments, 0, "email")
    assert_equal "[FILTERED]", captured.dig(:context, :job, :arguments, 0, "token")
    assert_equal "Starting #{ExplodingJob.name}", captured.dig(:context, :breadcrumbs, 0, :message)
    assert_equal "redis.get", captured.dig(:context, :dependencyCalls, 0, :name)
    assert_equal RUBY_VERSION, captured.dig(:context, :runtime, :rubyVersion)
    assert captured.dig(:context, :deployment, :service).present?
  ensure
    if had_report_error && original_report_error
      Logister.define_singleton_method(:report_error, original_report_error)
    elsif Logister.singleton_methods(false).include?(:report_error)
      Logister.singleton_class.send(:remove_method, :report_error)
    end
  end
end

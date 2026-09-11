# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::SelfReportingPolicy do
  it "is installed at boot and cannot be reenabled by a settings refresh" do
    config = Logister.configuration
    expect(config.capture_db_metrics).to be(false)
    expect(config.capture_request_spans).to be(false)
    config.capture_db_metrics = config.capture_request_spans = config.capture_sql_breadcrumbs = true
    Rails.application.config.x.logister.web_request_transactions_enabled = true
    InstanceConfiguration::Runtime.apply_observability!
    expect(config.capture_db_metrics).to be(false)
    expect(config.capture_request_spans).to be(false)
    expect(config.capture_sql_breadcrumbs).to be(false)
    expect(Rails.application.config.x.logister.web_request_transactions_enabled).to be(false)
  end

  it "filters both string and symbol payloads while retaining error context" do
    hook = Logister.configuration.before_notify
    %w[metric log transaction span check_in deployment].each do |type|
      expect(hook.call(event_type: type, level: "error")).to be(false)
      expect(hook.call("event_type" => type)).to be(false)
    end
    expect(hook.call(nil)).to be(false)
    expect(hook.call({})).to be(false)
    expect(hook.call(event_type: "error", context: { detail: "failure" })).to include(event_type: "error")
    expect(hook.call("event_type" => "error", "context" => {})).not_to be(false)
  end

  it "publishes only errors through the actual SDK reporter" do
    config = Logister.configuration.dup
    config.ignore_environments = []
    config.environment = "test"
    client = instance_double(Logister::Client, publish: true, shutdown: nil)
    allow(Logister::Client).to receive(:new).and_return(client)
    allow_any_instance_of(Logister::Reporter).to receive(:register_shutdown_hook)
    reporter = Logister::Reporter.new(config)

    reporter.report_metric(message: "db.query", value: 1)
    reporter.report_log(message: "routine")
    reporter.report_transaction(name: "request", duration_ms: 500)
    reporter.report_span(name: "request", duration_ms: 500)
    reporter.report_check_in(slug: "scheduler", status: "ok")
    reporter.report_error(RuntimeError.new("controlled failure"))

    expect(client).to have_received(:publish).once.with(hash_including(event_type: "error"))
    Logister::SelfReportingGuard.suppress { reporter.report_error(RuntimeError.new("recursive failure")) }
    expect(client).to have_received(:publish).once
  end
end

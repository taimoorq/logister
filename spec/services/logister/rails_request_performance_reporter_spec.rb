# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::RailsRequestPerformanceReporter do
  around do |example|
    config = Rails.application.config.x.logister
    previous_enabled = config.web_request_transactions_enabled
    previous_min_duration = config.web_request_min_duration_ms
    previous_log_min_duration = config.web_request_log_min_duration_ms

    config.web_request_transactions_enabled = true
    config.web_request_min_duration_ms = 250.0
    config.web_request_log_min_duration_ms = 1_000.0

    example.run
  ensure
    config.web_request_transactions_enabled = previous_enabled
    config.web_request_min_duration_ms = previous_min_duration
    config.web_request_log_min_duration_ms = previous_log_min_duration
  end

  it "reports slow Rails requests as Logister transactions with timing breakdowns" do
    allow(Logister).to receive(:report_transaction)
    allow(Logister).to receive(:report_log)

    described_class.call(
      controller: "ProjectsController",
      action: "show",
      method: "GET",
      path: "/projects/project-uuid",
      format: "text/html",
      status: 200,
      duration: 550.345,
      db_runtime: 120.111,
      view_runtime: 80.222,
      allocations: 42_000,
      params: { "controller" => "projects", "action" => "show", "period" => "24h", "cursor" => "abc" }
    )

    expect(Logister).to have_received(:report_transaction).with(
      hash_including(
        name: "GET ProjectsController#show",
        duration_ms: 550.35,
        level: "info",
        status: 200,
        context: hash_including(
          route: "ProjectsController#show",
          path: "/projects/project-uuid",
          duration_ms: 550.35,
          db_runtime_ms: 120.11,
          view_runtime_ms: 80.22,
          app_runtime_ms: 350.02,
          allocations: 42_000,
          param_keys: %w[cursor period]
        ),
        tags: { category: "web_performance", source: "rails" }
      )
    )
    expect(Logister).not_to have_received(:report_log)
  end

  it "adds a warning log for very slow Rails requests" do
    Rails.application.config.x.logister.web_request_log_min_duration_ms = 500.0
    allow(Logister).to receive(:report_transaction)
    allow(Logister).to receive(:report_log)

    described_class.call(
      controller: "DashboardController",
      action: "index",
      method: "GET",
      path: "/dashboard",
      status: 200,
      duration: 900.0
    )

    expect(Logister).to have_received(:report_log).with(
      hash_including(
        message: "Slow Rails request",
        level: "warn",
        context: hash_including(route: "DashboardController#index", duration_ms: 900.0),
        tags: { category: "web_performance", source: "rails" }
      )
    )
  end

  it "does not report requests below the configured duration threshold" do
    allow(Logister).to receive(:report_transaction)
    allow(Logister).to receive(:report_log)

    described_class.call(controller: "ProjectsController", action: "show", duration: 120.0)

    expect(Logister).not_to have_received(:report_transaction)
    expect(Logister).not_to have_received(:report_log)
  end
end

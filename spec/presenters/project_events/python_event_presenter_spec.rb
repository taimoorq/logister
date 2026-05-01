# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEvents::PythonEventPresenter do
  describe "#traceback_text" do
    it "formats structured frames like Python's traceback output" do
      presenter = described_class.new(
        nil,
        {
          "class" => "RuntimeError",
          "message" => "checkout failed",
          "frames" => [
            { "filename" => "/srv/app/worker.py", "lineno" => 10, "name" => "run", "line" => "checkout()" },
            { "filename" => "/srv/app/checkout.py", "lineno" => 41, "name" => "checkout", "line" => "raise RuntimeError('checkout failed')" }
          ]
        }
      )

      expect(presenter.traceback_text).to include("Traceback (most recent call last):")
      expect(presenter.traceback_text).to include('File "/srv/app/checkout.py", line 41, in checkout')
      expect(presenter.traceback_text).to include("RuntimeError: checkout failed")
    end
  end

  describe "#execution_details" do
    it "surfaces framework request and Celery task fields from logister-python" do
      event = Struct.new(:context).new(
        {
          "framework" => "fastapi",
          "status_code" => 500,
          "request" => {
            "method" => "POST",
            "path" => "/orders/42",
            "url" => "https://api.example.com/orders/42?debug=true",
            "headers" => { "X-Request-Id" => "req-42" },
            "path_params" => { "order_id" => "42" },
            "query_string" => "debug=true"
          },
          "task_name" => "orders.sync",
          "task_state" => "FAILURE",
          "task_args_count" => 1,
          "task_kwargs_keys" => [ "force" ],
          "queue" => "orders",
          "trace_id" => "trace-42"
        }
      )

      details = described_class.new(event).execution_details

      expect(details).to include(
        method: "POST",
        path: "/orders/42",
        status_code: 500,
        task_state: "FAILURE",
        queue: "orders",
        trace_id: "trace-42"
      )
      expect(details[:path_params]).to eq("order_id" => "42")
      expect(details[:headers]).to eq("X-Request-Id" => "req-42")
      expect(details[:task_kwargs_keys]).to eq([ "force" ])
    end
  end

  describe "#custom_context_details" do
    it "keeps app-specific default context separate from known Python telemetry" do
      event = Struct.new(:context).new(
        {
          "framework" => "celery",
          "runtime" => "python",
          "service" => "billing-worker",
          "feature_flags" => { "new_checkout" => true },
          "tenant_id" => "tenant-123",
          "task_name" => "billing.sync",
          "exception" => { "class" => "RuntimeError" }
        }
      )

      expect(described_class.new(event).custom_context_details).to eq(
        "service" => "billing-worker",
        "feature_flags" => { "new_checkout" => true },
        "tenant_id" => "tenant-123"
      )
    end
  end

  describe "#exception_chain" do
    it "collects nested cause and context exceptions with frames" do
      presenter = described_class.new(
        nil,
        {
          "class" => "RuntimeError",
          "cause" => {
            "class" => "ValueError",
            "message" => "invalid order",
            "frames" => [ { "filename" => "/srv/app/orders.py", "lineno" => 12, "name" => "load_order" } ]
          },
          "context" => {
            "class" => "KeyError",
            "message" => "customer_id"
          }
        }
      )

      chain = presenter.exception_chain

      expect(chain.map { |entry| entry[:label] }).to eq(%w[cause context])
      expect(chain.map { |entry| entry[:class_name] }).to eq(%w[ValueError KeyError])
      expect(chain.first[:frames].first[:method_name]).to eq("load_order")
    end
  end

  describe "#activity_summary" do
    it "builds a compact logger and execution summary" do
      event = Struct.new(:context).new(
        {
          "logger_name" => "inventory.cache",
          "logger" => {
            "function" => "refresh_cache",
            "filename" => "worker.py"
          },
          "task_name" => "inventory.refresh"
        }
      )

      expect(described_class.new(event).activity_summary).to eq("inventory.cache · refresh_cache() in worker.py · task inventory.refresh")
    end
  end
end

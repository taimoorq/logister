# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEvents::PythonEventPresenter do
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

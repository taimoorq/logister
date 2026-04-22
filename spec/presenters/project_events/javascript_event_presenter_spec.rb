# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEvents::JavascriptEventPresenter do
  describe "#exception_chain" do
    it "collects nested causes and context values" do
      presenter = described_class.new(
        nil,
        {
          "class" => "TypeError",
          "message" => "render failed",
          "cause" => {
            "class" => "Error",
            "message" => "missing state",
            "frames" => [ { "filename" => "/app/src/state.ts", "lineno" => 18, "name" => "readState" } ]
          },
          "context" => {
            "values" => [
              { "class" => "NetworkError", "message" => "upstream timeout" }
            ]
          }
        }
      )

      chain = presenter.exception_chain

      expect(chain.map { |entry| entry[:label] }).to eq(%w[cause context])
      expect(chain.map { |entry| entry[:class_name] }).to eq(%w[Error NetworkError])
      expect(chain.first[:frames].first[:method_name]).to eq("readState")
    end
  end

  describe "#activity_summary" do
    it "builds a compact logger and route summary" do
      event = Struct.new(:context).new(
        {
          "logger_name" => "console",
          "logger" => {
            "method" => "warn",
            "function" => "flushQueue",
            "filename" => "worker.js"
          },
          "route" => "/jobs/email-drain"
        }
      )

      expect(described_class.new(event).activity_summary).to eq("console · warn · flushQueue() in worker.js · /jobs/email-drain")
    end
  end
end

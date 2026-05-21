# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEvents::CfmlEventPresenter do
  describe "#frames" do
    it "accepts quria-style stacktrace frames" do
      presenter = described_class.new(
        nil,
        {
          "stacktrace" => [
            {
              "template" => "/var/www/index.cfm",
              "line" => 42,
              "type" => "Expression"
            }
          ]
        }
      )

      frames = presenter.frames

      expect(frames.size).to eq(1)
      expect(frames.first[:file]).to eq("/var/www/index.cfm")
      expect(frames.first[:line_number]).to eq(42)
      expect(frames.first[:method_name]).to eq("Expression")
    end
  end

  describe "#request_details" do
    it "prefers CGI details and falls back to generic request metadata" do
      event = Struct.new(:context).new(
        {
          "cgi" => {
            "SCRIPT_NAME" => "/index.cfm",
            "QUERY_STRING" => "order=123",
            "HTTP_USER_AGENT" => "ColdFusion"
          },
          "request" => {
            "method" => "POST",
            "client_ip" => "203.0.113.5",
            "url" => "https://app.example.com/index.cfm"
          }
        }
      )

      details = described_class.new(event).request_details

      expect(details[:script_name]).to eq("/index.cfm")
      expect(details[:request_method]).to eq("POST")
      expect(details[:query_string]).to eq("order=123")
      expect(details[:remote_addr]).to eq("203.0.113.5")
      expect(details[:http_user_agent]).to eq("ColdFusion")
      expect(details[:url]).to eq("https://app.example.com/index.cfm")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEvents::CfmlEventPresenter do
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

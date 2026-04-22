# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEvents::RequestContextPresenter do
  describe "#details" do
    it "normalizes request metadata from top-level and nested context keys" do
      event = Struct.new(:context).new(
        {
          "client_ip" => "203.0.113.8",
          "request" => {
            "headers" => { "Referer" => "https://app.example.com/orders" },
            "request_id" => "req_123",
            "url" => "https://app.example.com/orders/1"
          },
          "params" => {
            "controller" => "orders",
            "action" => "show"
          },
          "httpMethod" => "GET"
        }
      )

      details = described_class.new(event).details

      expect(details[:client_ip]).to eq("203.0.113.8")
      expect(details[:http_method]).to eq("GET")
      expect(details[:request_id]).to eq("req_123")
      expect(details[:url]).to eq("https://app.example.com/orders/1")
      expect(details[:referer]).to eq("https://app.example.com/orders")
      expect(details[:rails_action]).to eq("orders#show")
    end
  end
end

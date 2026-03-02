# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Health", type: :request do
  describe "GET /health/clickhouse" do
    context "when ClickHouse is disabled" do
      before do
        Rails.configuration.x.logister.clickhouse_enabled = false
      end

      it "returns 200 with status disabled" do
        get "/health/clickhouse"
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["status"]).to eq("disabled")
        expect(body["clickhouse_enabled"]).to eq(false)
      end
    end

    context "when ClickHouse is enabled and healthy" do
      before do
        Rails.configuration.x.logister.clickhouse_enabled = true
        client = instance_double(Logister::ClickhouseClient, enabled?: true, healthy?: true)
        allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
      end

      it "returns 200 with status ok" do
        get "/health/clickhouse"
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["status"]).to eq("ok")
        expect(body["clickhouse_enabled"]).to eq(true)
      end
    end

    context "when ClickHouse is enabled but unhealthy" do
      before do
        Rails.configuration.x.logister.clickhouse_enabled = true
        client = instance_double(Logister::ClickhouseClient, enabled?: true, healthy?: false)
        allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
      end

      it "returns 503 with status degraded" do
        get "/health/clickhouse"
        expect(response).to have_http_status(:service_unavailable)
        body = response.parsed_body
        expect(body["status"]).to eq("degraded")
        expect(body["clickhouse_enabled"]).to eq(true)
      end
    end
  end
end

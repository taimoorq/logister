# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::CheckIns", type: :request do
  describe "POST /api/v1/check_ins" do
    let(:auth_headers) { { "Authorization" => "Bearer test-token-one", "User-Agent" => "LogisterTest/1.0" } }

    it "creates a check_in event and updates monitor status" do
      expect {
        post api_v1_check_ins_path,
             params: {
               check_in: {
                 slug: "daily-billing-job",
                 status: "ok",
                 environment: "production",
                 expected_interval_seconds: 600,
                 release: "2026.03.02"
               }
             },
             as: :json,
             headers: auth_headers
      }.to change(IngestEvent, :count).by(1)

      expect(response).to have_http_status(:created)
      event = IngestEvent.order(:id).last
      expect(event).to be_check_in
      expect(event.context["check_in_slug"]).to eq("daily-billing-job")
      expect(event.context["expected_interval_seconds"]).to eq(600)

      monitor = CheckInMonitor.find_by(project_id: api_keys(:one).project_id, slug: "daily-billing-job")
      expect(monitor).to be_present
      expect(monitor.last_status).to eq("ok")
    end
  end
end

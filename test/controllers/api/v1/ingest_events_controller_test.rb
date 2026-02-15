require "test_helper"

class Api::V1::IngestEventsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @api_key = api_keys(:one)
  end

  test "creates event and enqueues clickhouse ingest job" do
    assert_enqueued_with(job: ClickhouseIngestJob) do
      post api_v1_ingest_events_path,
           params: {
             event: {
               event_type: "error",
               level: "error",
               message: "NoMethodError",
               fingerprint: "nomethoderror-checkout",
                context: {
                  environment: "production",
                  service: "checkout-app",
                  tags: { region: "us-east-1" },
                  exception: {
                    class: "NoMethodError",
                    backtrace: [ "app/services/checkout_service.rb:12", "app/controllers/checkout_controller.rb:8" ]
                  },
                  metadata: {
                    order_id: 123,
                    feature_flags: [ "new-checkout" ]
                  }
                }
              }
            },
           as: :json,
           headers: {
             "Authorization" => "Bearer test-token-one",
             "User-Agent" => "LogisterTest/1.0"
           }
    end

    assert_response :created

    created = IngestEvent.order(:id).last
    assert_equal @api_key.project_id, created.project_id
    assert_equal @api_key.id, created.api_key_id
    assert_equal "error", created.event_type
    assert_equal "NoMethodError", created.context.dig("exception", "class")
    assert_equal "new-checkout", created.context.dig("metadata", "feature_flags", 0)
  end

  test "rejects unauthorized token" do
    post api_v1_ingest_events_path,
         params: { event: { event_type: "error", message: "NoMethodError", occurred_at: Time.current.iso8601 } },
         as: :json,
         headers: { "Authorization" => "Bearer invalid-token" }

    assert_response :unauthorized
  end
end

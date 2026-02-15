require "test_helper"

class Logister::EventIngestorTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :payload

    def enabled?
      true
    end

    def insert_event!(attributes)
      @payload = attributes
    end
  end

  test "maps ingest event to clickhouse payload" do
    event = ingest_events(:one)
    event.update!(
      context: {
        environment: "production",
        service: "checkout-service",
        release: "sha123",
        exception: { class: "NoMethodError" },
        transaction_name: "POST /checkout",
        tags: { region: "us-east-1" },
        event_id: "7f2d5dca-0c4d-4f5e-9997-6f87f5460b88"
      }
    )

    client = FakeClient.new
    Logister::EventIngestor.new(
      event: event,
      request_context: { ip: "127.0.0.1", user_agent: "LogisterTest/1.0" },
      clickhouse_client: client
    ).call

    payload = client.payload
    assert_equal "7f2d5dca-0c4d-4f5e-9997-6f87f5460b88", payload[:event_id]
    assert_equal event.project_id, payload[:project_id]
    assert_equal event.api_key_id, payload[:api_key_id]
    assert_equal "error", payload[:event_type]
    assert_equal "production", payload[:environment]
    assert_equal "checkout-service", payload[:service]
    assert_equal "sha123", payload[:release]
    assert_equal "NoMethodError", payload[:exception_class]
    assert_equal "POST /checkout", payload[:transaction_name]
    assert_equal({ "region" => "us-east-1" }, payload[:tags])
    assert_equal "127.0.0.1", payload[:ip]
    assert_equal "LogisterTest/1.0", payload[:user_agent]
  end
end

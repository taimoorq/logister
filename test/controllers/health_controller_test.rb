require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "returns disabled when clickhouse integration is off" do
    Rails.configuration.x.logister.clickhouse_enabled = false

    get "/health/clickhouse"

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "disabled", body["status"]
  end
end

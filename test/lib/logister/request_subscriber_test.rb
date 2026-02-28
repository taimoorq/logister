require "test_helper"
require Rails.root.join("gems/logister-ruby/lib/logister")

class LogisterRequestSubscriberTest < ActiveSupport::TestCase
  test "captures request summary and sql breadcrumbs" do
    Logister::RequestSubscriber.install!
    Logister::ContextStore.reset_request_scope!

    original_capture_sql_breadcrumbs = Logister.configuration.capture_sql_breadcrumbs
    original_sql_min = Logister.configuration.sql_breadcrumb_min_duration_ms
    Logister.configuration.capture_sql_breadcrumbs = true
    Logister.configuration.sql_breadcrumb_min_duration_ms = 0.0

    ActiveSupport::Notifications.instrument(
      "process_action.action_controller",
      {
        request_id: "req-123",
        controller: "OrdersController",
        action: "show",
        status: 500,
        method: "GET",
        path: "/orders/123",
        db_runtime: 14.2,
        view_runtime: 8.1,
        allocations: 1200
      }
    ) { }

    ActiveSupport::Notifications.instrument(
      "sql.active_record",
      {
        name: "Order Load",
        sql: "SELECT * FROM orders WHERE id = 123",
        cached: false
      }
    ) { }

    summary = Logister::ContextStore.request_summary("req-123")
    breadcrumbs = Logister::ContextStore.breadcrumbs

    assert_equal 14.2, summary[:dbRuntimeMs]
    assert_equal 8.1, summary[:viewRuntimeMs]
    assert_equal "OrdersController#show completed", breadcrumbs.find { |item| item[:category] == "request" }[:message]
    assert_equal "Order Load query", breadcrumbs.find { |item| item[:category] == "db" }[:message]
  ensure
    Logister.configuration.capture_sql_breadcrumbs = original_capture_sql_breadcrumbs
    Logister.configuration.sql_breadcrumb_min_duration_ms = original_sql_min
    Logister::ContextStore.reset_request_scope!
    Logister::ContextStore.clear_request_summary("req-123")
  end
end

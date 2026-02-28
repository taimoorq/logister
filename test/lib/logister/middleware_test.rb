require "test_helper"
require "rack/mock"
require Rails.root.join("gems/logister-ruby/lib/logister")
require "ostruct"

class LogisterMiddlewareTest < ActiveSupport::TestCase
  test "captures rich request context for exceptions" do
    middleware = Logister::Middleware.new(
      lambda do |_env|
        Logister.add_breadcrumb(category: "test", message: "in-request breadcrumb", data: { phase: "before" })
        Logister.add_dependency(name: "stripe.charge", host: "api.stripe.com", method: "POST", status: 502, duration_ms: 183.6, kind: "http")
        raise RuntimeError, "boom"
      end
    )

    env = Rack::MockRequest.env_for(
      "https://dansnydermustgo.com/content/clinton-portis-expects-be-cut-season?page=6",
      "REQUEST_METHOD" => "GET",
      "HTTP_REFERER" => "https://dansnydermustgo.com/content/clinton-portis-expects-be-cut-season?page=6",
      "HTTP_COOKIE" => "session=abc123",
      "HTTP_USER_AGENT" => "Mozilla/5.0",
      "HTTP_X_FORWARDED_FOR" => "116.204.104.131, 66.241.125.180",
      "SERVER_PROTOCOL" => "HTTP/1.1",
      "REMOTE_ADDR" => "66.241.125.180"
    )
    env["action_dispatch.request_id"] = "d1585398-6817-41cd-bffb-0de457eea5b6"
    env["action_dispatch.request.parameters"] = {
      "controller" => "blogs",
      "action" => "show",
      "id" => "clinton-portis-expects-be-cut-season",
      "page" => "6"
    }
    env["action_dispatch.route_name"] = "content"
    env["action_dispatch.route_uri_pattern"] = "/content/:id"
    env["action_dispatch.parameter_filter"] = []
    env["action_controller.instance"] = OpenStruct.new(current_user: users(:one))
    env["HTTP_TRACEPARENT"] = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

    Logister::ContextStore.store_request_summary(
      env["action_dispatch.request_id"],
      { dbRuntimeMs: 12.4, viewRuntimeMs: 7.1, status: 500, allocations: 1234 }
    )
    captured = nil
    had_report_error = Logister.respond_to?(:report_error)
    original_report_error = Logister.method(:report_error) if had_report_error
    original_feature_flags_resolver = Logister.configuration.feature_flags_resolver
    original_dependency_resolver = Logister.configuration.dependency_resolver
    original_anonymize_ip = Logister.configuration.anonymize_ip
    Logister.configuration.feature_flags_resolver = ->(**) { { checkout_v2: true } }
    Logister.configuration.dependency_resolver = ->(**) { [ { name: "redis.get", kind: "redis", durationMs: 3.4 } ] }
    Logister.configuration.anonymize_ip = true
    Logister.define_singleton_method(:report_error) do |error, context:|
      captured = { error: error, context: context }
      true
    end

    assert_raises(RuntimeError) { middleware.call(env) }

    assert_kind_of RuntimeError, captured[:error]
    assert_equal "66.241.125.0", captured.dig(:context, :clientIp)
    assert_equal "GET", captured.dig(:context, :httpMethod)
    assert_equal "HTTP/1.1", captured.dig(:context, :httpVersion)
    assert_equal "blogs#show", captured.dig(:context, :railsAction)
    assert_equal "d1585398-6817-41cd-bffb-0de457eea5b6", captured.dig(:context, :requestId)
    assert_equal "[FILTERED]", captured.dig(:context, :headers, "Cookie")
    assert_equal "6", captured.dig(:context, :params, "page")
    assert_equal "GET", captured.dig(:context, :method)
    assert_equal 500, captured.dig(:context, :response, :status)
    assert_equal "content", captured.dig(:context, :route, :name)
    assert_equal "/content/:id", captured.dig(:context, :route, :pathTemplate)
    assert_equal users(:one).id.to_s, captured.dig(:context, :user, :id)
    assert_equal User.name, captured.dig(:context, :user, :class)
    assert_equal 64, captured.dig(:context, :user, :email_hash).to_s.length
    assert_equal "4bf92f3577b34da6a3ce929d0e0e4736", captured.dig(:context, :trace, :traceId)
    assert_equal "00f067aa0ba902b7", captured.dig(:context, :trace, :spanId)
    assert_equal true, captured.dig(:context, :trace, :sampled)
    assert_equal true, captured.dig(:context, :featureFlags, "checkout_v2")
    assert_equal 12.4, captured.dig(:context, :performance, :dbRuntimeMs)
    assert_equal 7.1, captured.dig(:context, :performance, :viewRuntimeMs)
    assert_equal "in-request breadcrumb", captured.dig(:context, :breadcrumbs, 0, :message)
    assert_equal "stripe.charge", captured.dig(:context, :dependencyCalls, 0, :name)
    assert_equal "redis.get", captured.dig(:context, :dependencyCalls, 1, :name)
    assert_equal RUBY_VERSION, captured.dig(:context, :runtime, :rubyVersion)
    assert_equal Rails.version, captured.dig(:context, :runtime, :railsVersion)
    assert captured.dig(:context, :deployment, :environment).present?
  ensure
    Logister.configuration.feature_flags_resolver = original_feature_flags_resolver
    Logister.configuration.dependency_resolver = original_dependency_resolver
    Logister.configuration.anonymize_ip = original_anonymize_ip
    if had_report_error && original_report_error
      Logister.define_singleton_method(:report_error, original_report_error)
    elsif Logister.singleton_methods(false).include?(:report_error)
      Logister.singleton_class.send(:remove_method, :report_error)
    end
  end
end

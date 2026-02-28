require "test_helper"

class ProjectEventsControllerTest < ActionDispatch::IntegrationTest
  test "owner can view event details" do
    sign_in users(:one)

    get project_event_path(projects(:one), ingest_events(:one))

    assert_response :success
    assert_includes response.body, "Stacktrace"
    assert_includes response.body, ingest_events(:one).message
  end

  test "shared user can view event details" do
    sign_in users(:two)

    get project_event_path(projects(:one), ingest_events(:one))

    assert_response :success
    assert_includes response.body, ingest_events(:one).message
  end

  test "non member cannot view event details" do
    sign_in users(:one)

    get project_event_path(projects(:two), ingest_events(:two))

    assert_response :not_found
  end

  test "event detail renders structured request context" do
    sign_in users(:one)

    event = IngestEvent.create!(
      project: projects(:one),
      api_key: api_keys(:one),
      event_type: :error,
      level: "error",
      message: "NoMethodError: undefined method",
      fingerprint: "nomethoderror-structured-context",
      context: {
        clientIp: "66.241.125.180",
        headers: {
          "Referer" => "https://dansnydermustgo.com/content/clinton-portis-expects-be-cut-season?page=6",
          "Version" => "HTTP/1.1"
        },
        httpMethod: "GET",
        params: {
          "page" => "6",
          "controller" => "blogs",
          "action" => "show",
          "id" => "clinton-portis-expects-be-cut-season"
        },
        requestId: "d1585398-6817-41cd-bffb-0de457eea5b6",
        url: "https://dansnydermustgo.com/content/clinton-portis-expects-be-cut-season?page=6"
      },
      occurred_at: Time.current
    )

    get project_event_path(projects(:one), event)

    assert_response :success
    assert_includes response.body, "clientIp"
    assert_includes response.body, "66.241.125.180"
    assert_includes response.body, "railsAction"
    assert_includes response.body, "blogs#show"
    assert_includes response.body, "httpVersion"
    assert_includes response.body, "HTTP/1.1"
  end
end

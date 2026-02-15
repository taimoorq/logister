require "test_helper"

class ProjectEventsControllerTest < ActionDispatch::IntegrationTest
  test "owner can view event details" do
    sign_in users(:one)

    get project_event_path(projects(:one), ingest_events(:one))

    assert_response :success
    assert_includes response.body, "Event details"
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
end

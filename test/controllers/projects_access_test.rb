require "test_helper"

class ProjectsAccessTest < ActionDispatch::IntegrationTest
  test "shared user can view shared project" do
    sign_in users(:two)

    get project_path(projects(:one))

    assert_response :success
    assert_includes response.body, projects(:one).name
  end

  test "shared user sees shared project in index" do
    sign_in users(:two)

    get projects_path

    assert_response :success
    assert_includes response.body, projects(:one).name
  end

  test "non member cannot view project" do
    sign_in users(:one)

    get project_path(projects(:two))

    assert_response :not_found
  end

  test "project show renders database load stats" do
    sign_in users(:one)
    IngestEvent.create!(
      project: projects(:one),
      api_key: api_keys(:one),
      event_type: :metric,
      level: "info",
      message: "db.query",
      fingerprint: "db-query-fresh",
      context: {
        duration_ms: 42.75,
        name: "User Load",
        sql: "SELECT \"users\".* FROM \"users\" WHERE \"users\".\"id\" = 1"
      },
      occurred_at: Time.current
    )

    get project_path(projects(:one))

    assert_response :success
    assert_includes response.body, "Database load (24h)"
    assert_includes response.body, "1 queries captured"
    assert_includes response.body, "42.75 ms"
    assert_includes response.body, "db.query"
  end
end

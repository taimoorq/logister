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
end

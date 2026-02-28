require "test_helper"

class RoutesProtectionTest < ActionDispatch::IntegrationTest
  test "unauthenticated user is redirected from protected pages" do
    get dashboard_path
    assert_redirected_to new_user_session_path

    get projects_path
    assert_redirected_to new_user_session_path

    delete project_path(projects(:one))
    assert_redirected_to new_user_session_path

    get admin_users_path
    assert_redirected_to new_user_session_path
  end

  test "shared member cannot create api keys" do
    sign_in users(:two)

    assert_no_difference("ApiKey.count") do
      post project_api_keys_path(projects(:one)), params: { api_key: { name: "forbidden" } }
    end

    assert_response :not_found
  end

  test "shared member cannot manage project memberships" do
    sign_in users(:two)

    assert_no_difference("ProjectMembership.count") do
      post project_project_memberships_path(projects(:one)), params: { project_membership: { email: "one@example.com" } }
    end

    assert_response :not_found
  end
end

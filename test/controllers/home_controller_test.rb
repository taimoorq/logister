require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "unauthenticated user sees landing page" do
    get root_path

    assert_response :success
    assert_includes response.body, "Catch Rails bugs before your users do."
    assert_includes response.body, "logister-ruby"
  end

  test "authenticated user is redirected from root to dashboard" do
    sign_in users(:one)

    get root_path

    assert_redirected_to dashboard_path
  end

  test "public legal and about pages are accessible" do
    get about_path
    assert_response :success
    assert_includes response.body, "About Logister"

    get privacy_path
    assert_response :success
    assert_includes response.body, "Privacy Policy"

    get terms_path
    assert_response :success
    assert_includes response.body, "Terms of Use"
  end
end

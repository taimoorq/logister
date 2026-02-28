require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "unauthenticated user sees landing page" do
    get root_path

    assert_response :success
    assert_includes response.body, "Catch Rails bugs before your users do."
    assert_includes response.body, "logister-ruby"
    assert_includes response.body, '<meta name="description"'
    assert_includes response.body, '<link rel="canonical" href="http://www.example.com/"'
    assert_includes response.body, "application/ld+json"
    assert_includes response.body, "/llms.txt"
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
    assert_includes response.body, "<title>About | Logister</title>"

    get privacy_path
    assert_response :success
    assert_includes response.body, "Privacy Policy"

    get terms_path
    assert_response :success
    assert_includes response.body, "Terms of Use"
  end

  test "llms txt is available" do
    get "/llms.txt"

    assert_response :success
    assert_includes response.body, "Logister is a free, open source bug capture"
  end
end

require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_admin_emails = ENV["LOGISTER_ADMIN_EMAILS"]
  end

  teardown do
    ENV["LOGISTER_ADMIN_EMAILS"] = @original_admin_emails
  end

  test "admin can view users index" do
    ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
    sign_in users(:one)

    get admin_users_path

    assert_response :success
    assert_includes response.body, "User Management"
    assert_includes response.body, users(:one).email
  end

  test "non-admin cannot view admin users index" do
    ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
    sign_in users(:two)

    get admin_users_path

    assert_redirected_to root_path
  end

  test "non-admin cannot delete users" do
    ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
    sign_in users(:two)

    assert_no_difference("User.count") do
      delete admin_user_path(users(:one))
    end

    assert_redirected_to root_path
  end

  test "admin can confirm an unconfirmed user" do
    ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
    sign_in users(:one)

    user = User.create!(
      email: "pending@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmation_token: "pending-token",
      confirmation_sent_at: Time.current
    )

    patch confirm_admin_user_path(user)

    assert_redirected_to admin_user_path(user)
    assert user.reload.confirmed?
  end

  test "admin can resend confirmation instructions" do
    ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
    sign_in users(:one)

    user = User.create!(
      email: "pending2@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmation_token: "pending-token-2",
      confirmation_sent_at: Time.current
    )

    assert_enqueued_jobs 1 do
      post resend_confirmation_admin_user_path(user)
    end

    assert_redirected_to admin_user_path(user)
  end

  test "admin can delete another user" do
    ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
    sign_in users(:one)

    assert_difference("User.count", -1) do
      delete admin_user_path(users(:two))
    end

    assert_redirected_to admin_users_path
  end

  test "admin cannot delete themselves" do
    ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
    sign_in users(:one)

    assert_no_difference("User.count") do
      delete admin_user_path(users(:one))
    end

    assert_redirected_to admin_user_path(users(:one))
  end
end

require "test_helper"

class Users::TurnstileTest < ActionDispatch::IntegrationTest
  setup do
    config = RailsCloudflareTurnstile.configuration
    @original = {
      enabled: config.enabled,
      mock_enabled: config.mock_enabled,
      fail_open: config.fail_open,
      site_key: config.site_key,
      secret_key: config.secret_key,
      timeout: config.timeout,
      validation_url: config.validation_url
    }

    config.enabled = true
    config.mock_enabled = false
    config.fail_open = false
    config.site_key = "test_site_key"
    config.secret_key = "test_secret_key"
    config.timeout = 0.1
    config.validation_url = "http://127.0.0.1:9/siteverify"
  end

  teardown do
    config = RailsCloudflareTurnstile.configuration
    @original.each { |k, v| config.public_send("#{k}=", v) }
  end

  test "blocks sign in when turnstile verification fails" do
    post user_session_path,
         params: {
           user: {
             email: users(:one).email,
             password: "password123"
           }
         }

    assert_redirected_to new_user_session_path
    assert_match("verification challenge", flash[:alert])
  end

  test "blocks sign up when turnstile verification fails" do
    assert_no_difference("User.count") do
      post user_registration_path,
           params: {
             user: {
               email: "new_user@example.com",
               password: "password123",
               password_confirmation: "password123"
             }
           }
    end

    assert_redirected_to new_user_registration_path
    assert_match("verification challenge", flash[:alert])
  end
end

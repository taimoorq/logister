require "test_helper"

class Users::ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "updates profile name" do
    patch profile_path, params: { user: { name: "Taimoor Q" } }

    assert_redirected_to profile_path
    assert_equal "Taimoor Q", @user.reload.name
  end

  test "strips blank name to nil" do
    patch profile_path, params: { user: { name: "   " } }

    assert_redirected_to profile_path
    assert_nil @user.reload.name
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  around do |example|
    original = ENV["LOGISTER_ADMIN_EMAILS"]
    example.run
  ensure
    ENV["LOGISTER_ADMIN_EMAILS"] = original
  end

  describe "GET /admin/users" do
    it "redirects non-admin to root" do
      ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
      sign_in users(:two)
      get admin_users_path
      expect(response).to redirect_to(root_path)
    end

    context "when admin" do
      before do
        ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
        sign_in users(:one)
      end

      it "returns success and user list" do
        get admin_users_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("User Management")
        expect(response.body).to include(users(:one).email)
      end
    end
  end

  describe "GET /admin/users/:uuid" do
    before do
      ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
      sign_in users(:one)
    end

    it "returns success and user detail" do
      get admin_user_path(users(:two))
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /admin/users/:uuid/confirm" do
    before do
      ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
      sign_in users(:one)
    end

    it "confirms unconfirmed user" do
      user = User.create!(
        email: "pending@example.com",
        password: "password123",
        password_confirmation: "password123",
        confirmation_token: "pending-token",
        confirmation_sent_at: Time.current
      )
      patch confirm_admin_user_path(user)
      expect(response).to redirect_to(admin_user_path(user))
      expect(user.reload).to be_confirmed
    end
  end

  describe "POST /admin/users/:uuid/resend_confirmation" do
    before do
      ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email
      sign_in users(:one)
    end

    it "enqueues confirmation email and redirects" do
      user = User.create!(
        email: "pending2@example.com",
        password: "password123",
        password_confirmation: "password123",
        confirmation_token: "pending-token-2",
        confirmation_sent_at: Time.current
      )
      expect {
        post resend_confirmation_admin_user_path(user)
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
      expect(response).to redirect_to(admin_user_path(user))
    end
  end

  describe "DELETE /admin/users/:uuid" do
    before { ENV["LOGISTER_ADMIN_EMAILS"] = users(:one).email }

    it "allows admin to delete another user" do
      sign_in users(:one)
      target = users(:two)
      expect {
        delete admin_user_path(target)
      }.to change(User, :count).by(-1)
      expect(response).to redirect_to(admin_users_path)
    end

    it "does not allow admin to delete themselves" do
      sign_in users(:one)
      expect {
        delete admin_user_path(users(:one))
      }.not_to change(User, :count)
      expect(response).to redirect_to(admin_user_path(users(:one)))
    end

    it "does not allow non-admin to delete" do
      sign_in users(:two)
      expect {
        delete admin_user_path(users(:one))
      }.not_to change(User, :count)
      expect(response).to redirect_to(root_path)
    end
  end
end

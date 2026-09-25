# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  include ActiveJob::TestHelper

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

      it "paginates filtered users in both directions and counts only their owned records" do
        time = Time.current
        users = create_list(:user, 52, name: "Directory sample", created_at: time)
        newest = users.last
        create_list(:project, 2, user: newest)
        project = newest.projects.first
        create_list(:api_key, 3, user: newest, project:)

        get admin_users_path, params: { q: "Directory sample" }
        expect(response).to have_http_status(:success)
        document = Nokogiri::HTML(response.body)
        rows = document.css("tr.inbox-row")
        expect(rows.length).to eq(50)
        expect(rows.first.css("td")[0].text).to eq(newest.email)
        expect(rows.first.css("td")[4].text).to eq("2")
        expect(rows.first.css("td")[5].text).to eq("3")
        first_emails = rows.map { |row| row.css("td").first.text }
        older = document.css("nav[aria-label='Pagination'] a").find { |link| link.text.strip == "Older" }

        get older["href"]
        expect(response).to have_http_status(:success)
        document = Nokogiri::HTML(response.body)
        expect(document.css("tr.inbox-row").map { |row| row.css("td").first.text }).to eq(users.first(2).reverse.map(&:email))
        newer = document.css("nav[aria-label='Pagination'] a").find { |link| link.text.strip == "Newer" }
        get newer["href"]
        expect(Nokogiri::HTML(response.body).css("tr.inbox-row").map { |row| row.css("td").first.text }).to eq(first_emails)
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

    it "tombstones owned projects before deleting another user" do
      sign_in users(:one)
      target = users(:two)
      clear_enqueued_jobs
      expect {
        delete admin_user_path(target)
      }.to change(ProjectPurge, :count).by(1)
        .and change(User, :count).by(0)
      expect(response).to redirect_to(admin_user_path(target))
      expect(target.projects.sole.reload).to be_purge_pending
      expect(ProjectPurgeJob).to have_been_enqueued
    end

    it "deletes a user immediately after all owned projects are gone" do
      sign_in users(:one)
      target = create(:user)

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

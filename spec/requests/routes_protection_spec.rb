# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Routes protection", type: :request do
  describe "unauthenticated access" do
    it "redirects from dashboard to sign in" do
      get dashboard_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects from projects index to sign in" do
      get projects_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects from project delete to sign in" do
      delete project_path(projects(:one))
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects from admin users to sign in" do
      get admin_users_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "shared member permissions" do
    before { sign_in users(:two) }

    it "cannot create api keys on shared project" do
      expect {
        post project_api_keys_path(projects(:one)), params: { api_key: { name: "forbidden" } }
      }.not_to change(ApiKey, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "cannot manage project memberships on shared project" do
      expect {
        post project_project_memberships_path(projects(:one)),
             params: { project_membership: { email: "one@example.com" } }
      }.not_to change(ProjectMembership, :count)
      expect(response).to have_http_status(:not_found)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project memberships", type: :request do
  let(:project) { projects(:one) }

  describe "POST /projects/:project_uuid/project_memberships" do
    it "requires authentication" do
      post project_project_memberships_path(project),
           params: { project_membership: { email: "other@example.com" } }
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "creates membership and redirects when user exists" do
        # User three must exist for email lookup
        user_three = User.create!(
          email: "three@example.com",
          password: "password123",
          password_confirmation: "password123",
          confirmed_at: Time.current
        )

        expect {
          post project_project_memberships_path(project),
               params: { project_membership: { email: "three@example.com" } }
        }.to change(ProjectMembership, :count).by(1)

        expect(response).to redirect_to(project_path(project))
        follow_redirect!
        expect(response.body).to include("Project shared with three@example.com")
        expect(project.members).to include(user_three)
      end

      it "redirects with alert when user not found" do
        post project_project_memberships_path(project),
             params: { project_membership: { email: "nobody@example.com" } }

        expect(response).to redirect_to(project_path(project))
        expect(flash[:alert]).to include("User not found")
      end

      it "redirects with alert when inviting self (owner)" do
        post project_project_memberships_path(project),
             params: { project_membership: { email: users(:one).email } }

        expect(response).to redirect_to(project_path(project))
        expect(flash[:alert]).to include("already own")
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns 404 (only owner can share)" do
        post project_project_memberships_path(project),
             params: { project_membership: { email: "other@example.com" } }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /projects/:project_uuid/project_memberships/:uuid" do
    it "requires authentication" do
      delete project_project_membership_path(project, project_memberships(:one))
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "removes membership and redirects" do
        membership = project_memberships(:one)
        expect {
          delete project_project_membership_path(project, membership)
        }.to change(ProjectMembership, :count).by(-1)
        expect(response).to redirect_to(project_path(project))
        follow_redirect!
        expect(response.body).to include("Access removed")
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns 404 (only owner can remove)" do
        membership = project_memberships(:one)
        expect {
          delete project_project_membership_path(project, membership)
        }.not_to change(ProjectMembership, :count)
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api keys", type: :request do
  let(:project) { projects(:one) }

  describe "POST /projects/:project_uuid/api_keys" do
    it "requires authentication" do
      post project_api_keys_path(project), params: { api_key: { name: "New key" } }
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "creates api key and redirects with notice" do
        expect {
          post project_api_keys_path(project), params: { api_key: { name: "CI key" } }
        }.to change(ApiKey, :count).by(1)

        expect(response).to redirect_to(project_path(project))
        follow_redirect!
        expect(response.body).to include("API key created")
        expect(flash[:new_api_key_token]).to be_present
      end

      it "assigns key to current user and project" do
        post project_api_keys_path(project), params: { api_key: { name: "CI key" } }
        key = ApiKey.last
        expect(key.user_id).to eq(users(:one).id)
        expect(key.project_id).to eq(project.id)
        expect(key.name).to eq("CI key")
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns 404 (only owner can create keys)" do
        expect {
          post project_api_keys_path(project), params: { api_key: { name: "Nope" } }
        }.not_to change(ApiKey, :count)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /projects/:project_uuid/api_keys/:uuid" do
    it "requires authentication" do
      delete project_api_key_path(project, api_keys(:one))
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "revokes api key and redirects" do
        key = api_keys(:one)
        delete project_api_key_path(project, key)
        expect(response).to redirect_to(project_path(project))
        expect(key.reload.revoked_at).to be_present
      end
    end

    context "when signed in as shared member" do
      before { sign_in users(:two) }

      it "returns 404 (only owner can revoke)" do
        key = api_keys(:one)
        expect {
          delete project_api_key_path(project, key)
        }.not_to change { key.reload.revoked_at }
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end

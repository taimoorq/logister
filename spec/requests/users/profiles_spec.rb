# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users::Profiles", type: :request do
  describe "GET /profile" do
    it "requires authentication" do
      get profile_path
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in" do
      before { sign_in users(:one) }

      it "returns success" do
        get profile_path
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /profile/edit" do
    before { sign_in users(:one) }

    it "returns success" do
      get edit_profile_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /profile" do
    before { sign_in users(:one) }

    it "updates profile and redirects" do
      patch profile_path, params: { user: { name: "New Name" } }
      expect(response).to redirect_to(profile_path)
      expect(users(:one).reload.name).to eq("New Name")
    end
  end
end

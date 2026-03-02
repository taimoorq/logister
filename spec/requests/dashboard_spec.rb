# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  describe "GET /dashboard" do
    it "requires authentication" do
      get dashboard_path
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in" do
      before { sign_in users(:one) }

      it "returns success" do
        get dashboard_path
        expect(response).to have_http_status(:success)
      end

      it "shows overview content and project count" do
        get dashboard_path
        expect(response.body).to include(projects(:one).name)
      end
    end
  end
end

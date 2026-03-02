# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home", type: :request do
  describe "GET /" do
    context "when unauthenticated" do
      it "returns success and shows landing content" do
        get root_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Catch Rails bugs before your users do.")
        expect(response.body).to include("logister-ruby")
        expect(response.body).to include("<meta name=\"description\"")
        expect(response.body).to include("application/ld+json")
        expect(response.body).to include("/llms.txt")
      end
    end

    context "when authenticated" do
      it "redirects to dashboard" do
        sign_in users(:one)
        get root_path
        expect(response).to redirect_to(dashboard_path)
      end
    end
  end

  describe "GET /about" do
    it "returns success and about content" do
      get about_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("About Logister")
      expect(response.body).to include("<title>About | Logister</title>")
    end
  end

  describe "GET /privacy" do
    it "returns success and privacy content" do
      get privacy_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Privacy Policy")
    end
  end

  describe "GET /terms" do
    it "returns success and terms content" do
      get terms_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Terms of Use")
    end
  end

  describe "GET /llms.txt" do
    it "returns success and llms content" do
      get "/llms.txt"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Logister is a free, open source bug capture")
    end
  end
end

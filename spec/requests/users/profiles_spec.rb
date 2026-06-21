# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

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

      it "shows the user's name in the profile dropdown when set" do
        users(:one).update!(name: "Taylor Example")

        get profile_path

        expect(profile_dropdown_label).to eq("Taylor Example")
      end

      it "shows the user's email in the profile dropdown when name is blank" do
        users(:one).update!(name: nil)

        get profile_path

        expect(profile_dropdown_label).to eq(users(:one).email)
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

  def profile_dropdown_label
    document = Nokogiri::HTML.parse(response.body)
    document.css("nav details summary span.truncate").last.text.squish
  end
end

# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Users::Passwords", type: :request do
  describe "GET /users/password/edit" do
    it "renders the reset password form in the Logister auth layout" do
      raw_token, encrypted_token = Devise.token_generator.generate(User, :reset_password_token)
      users(:one).update_columns(reset_password_token: encrypted_token, reset_password_sent_at: Time.current)

      get edit_user_password_path(reset_password_token: raw_token)

      expect(response).to have_http_status(:success)

      document = Nokogiri::HTML.parse(response.body)
      form = document.at_css("form[action='#{user_password_path}']")

      expect(document.at_css(".auth-shell")).to be_present
      expect(document.at_css(".auth-brand-panel").text).to include("Choose a new password")
      expect(document.at_css(".auth-form-title").text).to eq("Reset password")
      expect(form).to be_present
      expect(form.at_css("input[name='_method'][value='put']")).to be_present
      expect(form.at_css("input[name='user[reset_password_token]']")["value"]).to eq(raw_token)
      expect(form.at_css("input[name='user[password]']")).to be_present
      expect(form.at_css("input[name='user[password_confirmation]']")).to be_present
      expect(form.at_css("input[type='submit']")["value"]).to eq("Update password")
      expect(document.css(".auth-link").map(&:text)).to include("Sign in", "Sign up")
    end
  end
end

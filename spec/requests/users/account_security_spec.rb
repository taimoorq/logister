# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account security", type: :request do
  let(:password) { "correct-horse-battery" }
  let!(:user) { create(:user, email: "locked@example.com", password: password, password_confirmation: password) }

  before { ActionMailer::Base.deliveries.clear }

  # Turnstile runs in mock mode in the test environment.
  def attempt_sign_in(email: user.email, password: "wrong-password")
    post user_session_path, params: { user: { email: email, password: password }, "cf-turnstile-response" => "mocked" }
  end

  def signed_in?
    get dashboard_path
    response.successful?
  end

  describe "lockout after failed sign-in attempts" do
    it "locks the account on the tenth failure and emails an unlock link" do
      9.times { attempt_sign_in }
      expect(user.reload.access_locked?).to be(false)
      expect(user.failed_attempts).to eq(9)

      perform_enqueued_jobs { attempt_sign_in }

      expect(user.reload.access_locked?).to be(true)
      unlock_mail = ActionMailer::Base.deliveries.find { |mail| mail.to == [ user.email ] && mail.subject.match?(/unlock/i) }
      expect(unlock_mail).to be_present
      expect(unlock_mail.body.encoded).to include("/users/unlock?unlock_token=")
    end

    it "refuses the correct password while locked without revealing the lock" do
      user.lock_access!(send_instructions: false)

      attempt_sign_in(password: password)
      locked_message = flash[:alert]
      attempt_sign_in(email: "nobody@example.com", password: password)

      expect(locked_message).to eq(flash[:alert])
      expect(signed_in?).to be(false)
    end

    it "unlocks automatically after an hour" do
      user.lock_access!(send_instructions: false)

      travel 61.minutes do
        attempt_sign_in(password: password)

        expect(signed_in?).to be(true)
        expect(user.reload.access_locked?).to be(false)
        expect(user.failed_attempts).to eq(0)
      end
    end

    it "unlocks from the emailed link" do
      user.lock_access!(send_instructions: false)
      raw_token = user.send_unlock_instructions

      get user_unlock_path(unlock_token: raw_token)

      expect(response).to redirect_to(new_user_session_path)
      expect(user.reload.access_locked?).to be(false)
      attempt_sign_in(password: password)
      expect(signed_in?).to be(true)
    end

    it "answers unlock requests the same way for known and unknown emails" do
      user.lock_access!(send_instructions: false)

      perform_enqueued_jobs { post user_unlock_path, params: { user: { email: user.email }, "cf-turnstile-response" => "mocked" } }
      known = [ response.status, response.location, flash[:notice] ]
      post user_unlock_path, params: { user: { email: "nobody@example.com" }, "cf-turnstile-response" => "mocked" }
      unknown = [ response.status, response.location, flash[:notice] ]

      expect(known).to eq(unknown)
      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ user.email ] ])
    end

    it "renders the unlock request form in the auth layout" do
      get new_user_unlock_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Resend unlock instructions", "auth-shell")
    end
  end

  describe "idle session timeout" do
    it "signs the user out after the configured idle time" do
      attempt_sign_in(password: password)
      expect(signed_in?).to be(true)

      travel(Devise.timeout_in + 1.minute) do
        get dashboard_path
        expect(response).to redirect_to(dashboard_path)

        follow_redirect!
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    it "defaults to two idle hours" do
      expect(Devise.timeout_in).to eq(120.minutes)
    end
  end

  describe "password length" do
    it "requires 12 characters for a new password" do
      expect(build(:user, password: "a" * 11, password_confirmation: "a" * 11)).not_to be_valid
      expect(build(:user, password: "a" * 12, password_confirmation: "a" * 12)).to be_valid
    end

    it "still signs in an account whose existing password predates the minimum" do
      user.update_columns(encrypted_password: Devise::Encryptor.digest(User, "short1"))

      attempt_sign_in(password: "short1")

      expect(signed_in?).to be(true)
    end

    it "rejects a short password on sign-up" do
      post user_registration_path, params: {
        user: { email: "new-signup@example.com", password: "elevenchars", password_confirmation: "elevenchars" },
        "cf-turnstile-response" => "mocked"
      }

      expect(User.exists?(email: "new-signup@example.com")).to be(false)
    end
  end

  describe "paranoid password reset" do
    it "answers the same way for known and unknown emails" do
      post user_password_path, params: { user: { email: user.email }, "cf-turnstile-response" => "mocked" }
      known = [ response.status, response.location, flash[:notice] ]
      post user_password_path, params: { user: { email: "nobody@example.com" }, "cf-turnstile-response" => "mocked" }
      unknown = [ response.status, response.location, flash[:notice] ]

      expect(known).to eq(unknown)
    end
  end

  describe "change notifications" do
    it "emails the account when its password or email changes" do
      perform_enqueued_jobs do
        user.update!(password: "a-brand-new-password", password_confirmation: "a-brand-new-password")
        user.update!(email: "moved@example.com")
      end

      subjects = ActionMailer::Base.deliveries.select { |mail| mail.to == [ "locked@example.com" ] }.map(&:subject)
      expect(subjects).to include("Password Changed", "Email Changed")
    end
  end
end

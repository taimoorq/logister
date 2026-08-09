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

      it "shows only safe metadata for the user's active and recently ended CLI sessions" do
        active = create(
          :cli_access_token,
          user: users(:one),
          name: "Work laptop",
          scopes: [ "projects:read", "events:read" ],
          last_used_at: 2.hours.ago
        )
        create(:cli_access_token, :project_limited, user: users(:one), name: "Release terminal")
        create(:cli_access_token, :revoked, user: users(:one), name: "Old laptop", revoked_at: 2.days.ago)
        expired = create(:cli_access_token, user: users(:one), name: "Expired shell")
        expired.update_columns(expires_at: 3.days.ago, updated_at: Time.current)
        old = create(:cli_access_token, user: users(:one), name: "Long-ended terminal")
        old.update_columns(revoked_at: 31.days.ago, updated_at: Time.current)
        another_user_token = create(:cli_access_token, user: users(:two), name: "Someone else's terminal")

        get profile_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Work laptop", "Release terminal", "Old laptop", "Expired shell")
        expect(response.body).to include("projects:read, events:read")
        expect(response.body).to include("All accessible projects", "Selected projects")
        expect(response.body).not_to include("Long-ended terminal", "Someone else's terminal")
        expect(response.body).not_to include(active.token_digest, active.plain_token, another_user_token.token_digest)

        document = Nokogiri::HTML.parse(response.body)
        active_rows = document.css("#active-cli-sessions tr")
        recent_rows = document.css("#recent-cli-sessions tr")
        revoke_form = document.at_css("form[action='#{profile_cli_access_token_path(active.uuid)}']")

        expect(active_rows.map { |row| row["data-cli-session-state"] }).to all(eq("active"))
        expect(recent_rows.map { |row| row["data-cli-session-state"] }).to contain_exactly("revoked", "expired")
        expect(revoke_form["data-turbo-confirm"]).to include("stop working immediately")
        expect(revoke_form.at_css("input[name='_method'][value='delete']")).to be_present
        expect(document.css("turbo-frame")).to be_empty
      end

      it "bounds active and recently ended session rows" do
        users(:one).cli_access_tokens.delete_all
        snapshot = Time.current

        27.times do |index|
          create(
            :cli_access_token,
            user: users(:one),
            name: "Active session #{index}",
            created_at: snapshot - index.minutes
          )
        end
        12.times do |index|
          create(
            :cli_access_token,
            user: users(:one),
            name: "Ended session #{index}",
            revoked_at: snapshot - index.minutes,
            created_at: snapshot - index.minutes
          )
        end

        get profile_path

        document = Nokogiri::HTML.parse(response.body)
        expect(document.css("#active-cli-sessions tr").length).to eq(25)
        expect(document.css("#recent-cli-sessions tr").length).to eq(10)
        expect(response.body).to include("Active session 0", "Ended session 0")
        expect(response.body).not_to include("Active session 26", "Ended session 11")
        expect(response.body).to include(
          "Showing the 25 most recently created active sessions.",
          "Showing the 10 most recent sessions ended in the last 30 days."
        )
      end

      it "renders an instructional empty state when no current or recent sessions exist" do
        users(:one).cli_access_tokens.delete_all

        get profile_path

        expect(response.body).to include("No active or recently ended CLI sessions")
        expect(response.body).to include("logister auth login")
        expect(response.body).not_to include("Revoke all active sessions")
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

  describe "DELETE /profile/cli-access-tokens/:uuid" do
    it "requires authentication" do
      token = create(:cli_access_token, user: users(:one))

      delete profile_cli_access_token_path(token.uuid)

      expect(response).to redirect_to(new_user_session_path)
      expect(token.reload.revoked_at).to be_nil
    end

    it "revokes an owned active session and redirects with a specific confirmation" do
      sign_in users(:one)
      token = create(:cli_access_token, user: users(:one), name: "Work laptop")

      delete profile_cli_access_token_path(token.uuid)

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(profile_path(anchor: "cli-sessions"))
      expect(token.reload.revoked_at).to be_present

      follow_redirect!
      expect(response.body).to include("CLI session revoked. That terminal must sign in again to access Logister.")
      expect(response.body).to include("Work laptop", "Revoked")
    end

    it "does not change the revocation time when the session is already inactive" do
      sign_in users(:one)
      revoked_at = 2.days.ago
      token = create(:cli_access_token, user: users(:one), revoked_at: revoked_at)

      delete profile_cli_access_token_path(token.uuid)

      expect(response).to have_http_status(:see_other)
      expect(token.reload.revoked_at).to be_within(0.001).of(revoked_at)
      expect(flash[:notice]).to eq("That CLI session was already inactive.")
    end

    it "returns a neutral not found response for another user's session" do
      sign_in users(:one)
      token = create(:cli_access_token, user: users(:two))

      delete profile_cli_access_token_path(token.uuid)

      expect(response).to have_http_status(:not_found)
      expect(token.reload.revoked_at).to be_nil
    end
  end

  describe "DELETE /profile/cli-access-tokens" do
    it "requires authentication" do
      token = create(:cli_access_token, user: users(:one))

      delete profile_cli_access_tokens_path

      expect(response).to redirect_to(new_user_session_path)
      expect(token.reload.revoked_at).to be_nil
    end

    it "revokes every active session owned by the current user and no others" do
      sign_in users(:one)
      active_tokens = create_list(:cli_access_token, 2, user: users(:one))
      expired = create(:cli_access_token, user: users(:one))
      expired.update_columns(expires_at: 1.minute.ago, updated_at: Time.current)
      already_revoked_at = 2.days.ago
      already_revoked = create(:cli_access_token, :revoked, user: users(:one), revoked_at: already_revoked_at)
      another_user_token = create(:cli_access_token, user: users(:two))

      delete profile_cli_access_tokens_path

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(profile_path(anchor: "cli-sessions"))
      expect(active_tokens.map { |token| token.reload.revoked_at }).to all(be_present)
      expect(expired.reload.revoked_at).to be_nil
      expect(already_revoked.reload.revoked_at).to be_within(0.001).of(already_revoked_at)
      expect(another_user_token.reload.revoked_at).to be_nil

      follow_redirect!
      expect(response.body).to include("Revoked 2 active CLI sessions. Those terminals must sign in again.")
    end

    it "reports a no-op when the user has no active sessions" do
      sign_in users(:one)
      users(:one).cli_access_tokens.delete_all

      delete profile_cli_access_tokens_path

      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq("No active CLI sessions needed revoking.")
    end
  end

  def profile_dropdown_label
    document = Nokogiri::HTML.parse(response.body)
    document.css("nav details summary span.truncate").last.text.squish
  end
end

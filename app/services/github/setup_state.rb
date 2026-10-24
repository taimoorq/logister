# frozen_string_literal: true

module Github
  # Signed, short-lived `state` for the GitHub App install URL. GitHub echoes it back
  # to the setup callback, which binds the callback to the user who started the install.
  class SetupState
    PURPOSE = "github_app_setup"
    EXPIRES_IN = 1.hour

    Payload = Data.define(:user_id, :project_uuid)

    def self.generate(user:, project: nil)
      verifier.generate(
        {
          "user_id" => user.id,
          "project_uuid" => project&.uuid,
          "nonce" => SecureRandom.urlsafe_base64(16)
        }.compact,
        purpose: PURPOSE,
        expires_in: EXPIRES_IN
      )
    end

    def self.verify(token, user:)
      return if token.blank? || user.blank?

      data = verifier.verified(token.to_s, purpose: PURPOSE)
      return unless data.is_a?(Hash) && data["user_id"].to_s == user.id.to_s

      Payload.new(user_id: user.id, project_uuid: data["project_uuid"].to_s.presence)
    rescue ArgumentError, JSON::ParserError
      nil
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
  end
end

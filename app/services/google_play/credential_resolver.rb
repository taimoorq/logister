# frozen_string_literal: true

require "base64"
require "digest"
require "net/http"
require "openssl"

module GooglePlay
  class CredentialResolver
    SCOPE = "https://www.googleapis.com/auth/playdeveloperreporting"

    def initialize(reference)
      @reference = reference.to_s
    end

    def access_token
      raw = credential_value
      return raw unless raw.lstrip.start_with?("{")

      service_account_token(JSON.parse(raw))
    end

    private

    attr_reader :reference

    def credential_value
      raise ArgumentError, "credential reference must be an environment variable name" unless reference.match?(/\A[A-Z][A-Z0-9_]*\z/)

      ENV.fetch(reference) { raise ArgumentError, "credential reference #{reference} is not configured" }.to_s.strip.presence ||
        raise(ArgumentError, "credential reference #{reference} is empty")
    end

    def service_account_token(credentials)
      required = credentials.values_at("client_email", "private_key", "token_uri")
      raise ArgumentError, "service account JSON is missing client_email, private_key, or token_uri" if required.any?(&:blank?)

      key = [ "google_play_access_token", reference, Digest::SHA256.hexdigest(credentials.fetch("private_key")) ]
      Rails.cache.fetch(key, expires_in: 50.minutes) { exchange_assertion(credentials) }
    end

    def exchange_assertion(credentials)
      now = Time.current.to_i
      header = { alg: "RS256", typ: "JWT" }
      claims = {
        iss: credentials.fetch("client_email"),
        scope: SCOPE,
        aud: credentials.fetch("token_uri"),
        iat: now,
        exp: now + 3600
      }
      signing_input = "#{encode(header.to_json)}.#{encode(claims.to_json)}"
      signature = OpenSSL::PKey::RSA.new(credentials.fetch("private_key")).sign(OpenSSL::Digest::SHA256.new, signing_input)
      assertion = "#{signing_input}.#{encode(signature)}"
      uri = URI(credentials.fetch("token_uri"))
      response = Net::HTTP.post_form(uri, grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: assertion)
      payload = JSON.parse(response.body)
      raise "Google OAuth token exchange failed (#{response.code}): #{payload['error_description'] || payload['error']}" unless response.is_a?(Net::HTTPSuccess)

      payload.fetch("access_token")
    end

    def encode(value)
      Base64.urlsafe_encode64(value, padding: false)
    end
  end
end

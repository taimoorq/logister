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
      raw = IntegrationCredentialReference.fetch!(reference)
      return raw unless raw.lstrip.start_with?("{")

      service_account_token(parse_service_account(raw))
    end

    private

    attr_reader :reference

    def parse_service_account(raw)
      credentials = JSON.parse(raw)
      required = credentials.is_a?(Hash) ? credentials.values_at("client_email", "private_key", "token_uri") : [ nil ]
      raise IntegrationCredentialReference::Error.new(:unparseable) if required.any?(&:blank?)

      credentials
    rescue JSON::ParserError
      raise IntegrationCredentialReference::Error.new(:unparseable)
    end

    def service_account_token(credentials)
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
      signature = signing_key(credentials.fetch("private_key")).sign(OpenSSL::Digest::SHA256.new, signing_input)
      assertion = "#{signing_input}.#{encode(signature)}"
      uri = URI(credentials.fetch("token_uri"))
      response = Net::HTTP.post_form(uri, grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: assertion)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("Google OAuth token exchange failed status=#{response.code}")
        raise IntegrationCredentialReference::Error.new(:rejected)
      end

      JSON.parse(response.body).fetch("access_token")
    rescue JSON::ParserError, KeyError
      raise IntegrationCredentialReference::Error.new(:rejected)
    end

    def signing_key(pem)
      OpenSSL::PKey::RSA.new(pem)
    rescue OpenSSL::PKey::PKeyError
      raise IntegrationCredentialReference::Error.new(:unparseable)
    end

    def encode(value)
      Base64.urlsafe_encode64(value, padding: false)
    end
  end
end

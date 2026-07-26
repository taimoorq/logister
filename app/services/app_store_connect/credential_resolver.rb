# frozen_string_literal: true

require "base64"
require "digest"
require "openssl"

module AppStoreConnect
  class CredentialResolver
    AUDIENCE = "appstoreconnect-v1"
    TOKEN_LIFETIME = 19.minutes

    def initialize(issuer_id:, key_id:, credential_reference:)
      @issuer_id = issuer_id.to_s
      @key_id = key_id.to_s
      @credential_reference = credential_reference.to_s
    end

    def token
      private_key = credential_value
      cache_key = [ "app_store_connect_token", issuer_id, key_id, Digest::SHA256.hexdigest(private_key) ]
      Rails.cache.fetch(cache_key, expires_in: 15.minutes) { generate_token(private_key) }
    end

    private

    attr_reader :issuer_id, :key_id, :credential_reference

    def credential_value
      unless credential_reference.match?(/\A[A-Z][A-Z0-9_]*\z/)
        raise ArgumentError, "credential reference must be an environment variable name"
      end

      ENV.fetch(credential_reference) { raise ArgumentError, "credential reference #{credential_reference} is not configured" }.to_s.strip.presence ||
        raise(ArgumentError, "credential reference #{credential_reference} is empty")
    end

    def generate_token(private_key)
      now = Time.current.to_i
      header = { alg: "ES256", kid: key_id, typ: "JWT" }
      claims = { iss: issuer_id, iat: now, exp: now + TOKEN_LIFETIME.to_i, aud: AUDIENCE }
      signing_input = "#{encode(header.to_json)}.#{encode(claims.to_json)}"
      key = OpenSSL::PKey.read(private_key)
      raise ArgumentError, "App Store Connect private key must be an EC key" unless key.is_a?(OpenSSL::PKey::EC)

      der_signature = key.sign(OpenSSL::Digest::SHA256.new, signing_input)
      "#{signing_input}.#{encode(jwt_signature(der_signature))}"
    rescue OpenSSL::PKey::PKeyError, OpenSSL::ASN1::ASN1Error => error
      raise ArgumentError, "App Store Connect private key is invalid: #{error.message}"
    end

    def jwt_signature(der_signature)
      sequence = OpenSSL::ASN1.decode(der_signature)
      sequence.value.map { |integer| [ integer.value.to_i.to_s(16).rjust(64, "0") ].pack("H*") }.join
    end

    def encode(value)
      Base64.urlsafe_encode64(value, padding: false)
    end
  end
end

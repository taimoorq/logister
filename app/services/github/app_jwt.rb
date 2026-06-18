# frozen_string_literal: true

require "base64"
require "openssl"

module Github
  class AppJwt
    class NotConfigured < StandardError; end

    def initialize(config: Logister::GithubAppConfig)
      @config = config
    end

    def token
      raise NotConfigured, "GitHub App ID and private key are required" unless config.configured?

      issued_at = Time.now.to_i - 60
      expires_at = issued_at + 9.minutes.to_i
      payload = [
        encode_json(alg: "RS256", typ: "JWT"),
        encode_json(iat: issued_at, exp: expires_at, iss: config.app_id)
      ].join(".")
      signature = private_key.sign(OpenSSL::Digest::SHA256.new, payload)

      "#{payload}.#{Base64.urlsafe_encode64(signature, padding: false)}"
    end

    private

    attr_reader :config

    def encode_json(payload)
      Base64.urlsafe_encode64(payload.to_json, padding: false)
    end

    def private_key
      OpenSSL::PKey.read(config.private_key_pem)
    end
  end
end

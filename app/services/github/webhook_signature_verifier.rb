# frozen_string_literal: true

require "openssl"

module Github
  class WebhookSignatureVerifier
    SIGNATURE_PREFIX = "sha256="

    def initialize(secret: Logister::GithubAppConfig.webhook_secret)
      @secret = secret.to_s
    end

    def configured?
      secret.present?
    end

    def valid?(payload:, signature:)
      return false unless configured?

      expected = "#{SIGNATURE_PREFIX}#{OpenSSL::HMAC.hexdigest("SHA256", secret, payload.to_s)}"
      supplied = signature.to_s
      return false if supplied.blank? || supplied.bytesize != expected.bytesize

      ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
    end

    private

    attr_reader :secret
  end
end

# frozen_string_literal: true

require "uri"

module Logister
  class GithubAppConfig
    DEFAULT_API_URL = "https://api.github.com"
    DEFAULT_API_VERSION = "2026-03-10"
    DEFAULT_WEB_URL = "https://github.com"
    STATELESS_S2S_TOKEN_VALUES = %w[enabled disabled].freeze

    class << self
      def configured?
        app_id.present? && private_key_pem.present?
      end

      def app_id
        ENV["LOGISTER_GITHUB_APP_ID"].to_s.strip.presence
      end

      def private_key_pem
        ENV["LOGISTER_GITHUB_APP_PRIVATE_KEY"].to_s.gsub("\\n", "\n").strip.presence
      end

      def webhook_secret
        ENV["LOGISTER_GITHUB_WEBHOOK_SECRET"].to_s.strip.presence
      end

      def webhook_configured?
        webhook_secret.present?
      end

      def app_slug
        ENV["LOGISTER_GITHUB_APP_SLUG"].to_s.strip.presence
      end

      def install_url(state: nil)
        base_url = ENV["LOGISTER_GITHUB_APP_INSTALL_URL"].to_s.strip.presence ||
          (app_slug.present? ? "#{web_url}/apps/#{app_slug}/installations/new" : nil)
        return if base_url.blank?

        uri = URI(base_url)
        query = URI.decode_www_form(uri.query.to_s)
        query << [ "state", state ] if state.present?
        uri.query = query.presence&.then { |pairs| URI.encode_www_form(pairs) }
        uri.to_s
      rescue URI::InvalidURIError
        nil
      end

      def api_url
        ENV.fetch("LOGISTER_GITHUB_API_URL", DEFAULT_API_URL).to_s.delete_suffix("/")
      end

      def api_version
        ENV.fetch("LOGISTER_GITHUB_API_VERSION", DEFAULT_API_VERSION).to_s.strip
      end

      def web_url
        ENV.fetch("LOGISTER_GITHUB_WEB_URL", DEFAULT_WEB_URL).to_s.delete_suffix("/")
      end

      def stateless_s2s_token_override
        value = ENV["LOGISTER_GITHUB_STATELESS_S2S_TOKEN"].to_s.strip.downcase
        STATELESS_S2S_TOKEN_VALUES.include?(value) ? value : nil
      end
    end
  end
end

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
        InstanceConfiguration.value("github.app_id").to_s.strip.presence
      end

      def private_key_pem
        InstanceConfiguration.value("github.private_key").to_s.gsub("\\n", "\n").strip.presence
      end

      def webhook_secret
        InstanceConfiguration.value("github.webhook_secret").to_s.strip.presence
      end

      def webhook_configured?
        webhook_secret.present?
      end

      def app_slug
        InstanceConfiguration.value("github.app_slug").to_s.strip.presence
      end

      def install_url(state: nil)
        base_url = InstanceConfiguration.value("github.install_url").to_s.strip.presence ||
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
        InstanceConfiguration.value("github.api_url").to_s.delete_suffix("/")
      end

      def api_version
        InstanceConfiguration.value("github.api_version").to_s.strip
      end

      def web_url
        InstanceConfiguration.value("github.web_url").to_s.delete_suffix("/")
      end

      def stateless_s2s_token_override
        value = InstanceConfiguration.value("github.stateless_s2s_token").to_s.strip.downcase
        STATELESS_S2S_TOKEN_VALUES.include?(value) ? value : nil
      end
    end
  end
end

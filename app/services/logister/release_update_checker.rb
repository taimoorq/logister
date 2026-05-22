require "json"
require "net/http"
require "uri"

module Logister
  class ReleaseUpdateChecker
    DEFAULT_REPOSITORY = "taimoorq/logister"
    CACHE_TTL = 24.hours
    REQUEST_TIMEOUT = 1.5

    Result = Struct.new(:current_version, :latest_version, :release_name, :release_url, :published_at, keyword_init: true) do
      def notification_key
        "release_update:#{latest_version}"
      end
    end

    class << self
      def call
        new.call
      end
    end

    def call
      return nil unless enabled?

      current = current_version
      latest = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL, race_condition_ttl: 5.minutes) { fetch_latest_release }
      return nil if current.blank? || latest.blank?

      latest_version = normalize_tag(latest.fetch("tag_name", nil))
      return nil unless newer_release?(latest_version, normalize_tag(current))

      Result.new(
        current_version: current,
        latest_version: latest_version,
        release_name: latest["name"].presence || latest_version,
        release_url: latest["html_url"].presence || releases_url,
        published_at: latest["published_at"]
      )
    rescue StandardError => e
      Rails.logger.info("release update check failed: #{e.class} #{e.message}")
      nil
    end

    private

    def enabled?
      default = Rails.env.test? ? "false" : "true"
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("LOGISTER_UPDATE_CHECKS_ENABLED", default))
    end

    def current_version
      configured = ENV["LOGISTER_RELEASE"].to_s.strip
      return normalize_tag(configured) if release_tag?(configured)

      changelog_version
    end

    def changelog_version
      match = File.read(Rails.root.join("CHANGELOG.md")).match(/^##\s+(v[0-9][^\s]*)\s+-\s+[0-9]{4}-[0-9]{2}-[0-9]{2}\s*$/)
      normalize_tag(match[1]) if match
    end

    def fetch_latest_release
      uri = URI("https://api.github.com/repos/#{repository}/releases/latest")
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["User-Agent"] = "Logister release checker"
      request["Authorization"] = "Bearer #{ENV["LOGISTER_GITHUB_TOKEN"]}" if ENV["LOGISTER_GITHUB_TOKEN"].present?

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: REQUEST_TIMEOUT, read_timeout: REQUEST_TIMEOUT) do |http|
        http.request(request)
      end
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def repository
      ENV["LOGISTER_RELEASE_REPOSITORY"].to_s.strip.presence || DEFAULT_REPOSITORY
    end

    def cache_key
      [ "logister", "release_update", repository ]
    end

    def releases_url
      "https://github.com/#{repository}/releases"
    end

    def release_tag?(value)
      normalize_tag(value).match?(/\A[0-9]+(\.[0-9A-Za-z-]+)+\z/)
    end

    def normalize_tag(value)
      value.to_s.strip.delete_prefix("v")
    end

    def newer_release?(latest_version, current_version)
      return false if latest_version.blank? || current_version.blank?

      Gem::Version.new(latest_version) > Gem::Version.new(current_version)
    rescue ArgumentError
      false
    end
  end
end

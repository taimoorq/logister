# frozen_string_literal: true

require "net/http"
require "cgi"

module AppStoreConnect
  class Client
    BASE_URL = "https://api.appstoreconnect.apple.com"
    Error = Class.new(StandardError)

    def initialize(setting, base_url: BASE_URL)
      @setting = setting
      @base_url = base_url
    end

    def app_for_bundle_id(bundle_identifier)
      payload = get("/v1/apps", "filter[bundleId]" => bundle_identifier, "limit" => 2)
      apps = Array(payload["data"])
      raise Error, "No App Store Connect app matches #{bundle_identifier}" if apps.empty?
      raise Error, "More than one App Store Connect app matches #{bundle_identifier}" if apps.size > 1

      apps.first
    end

    def performance_metrics(app_id)
      get("/v1/apps/#{CGI.escapeURIComponent(app_id.to_s)}/perfPowerMetrics", "filter[platform]" => "IOS")
    end

    private

    attr_reader :setting, :base_url

    def get(path, params = {})
      uri = URI.join(base_url, path)
      uri.query = URI.encode_www_form(params) if params.present?
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 30
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{credential_resolver.token}"
      request["Accept"] = "application/json"
      response = http.request(request)
      payload = response.body.present? ? JSON.parse(response.body) : {}
      return payload if response.is_a?(Net::HTTPSuccess)

      message = Array(payload["errors"]).filter_map { |error| error["detail"] || error["title"] }.join("; ").presence || response.message
      retry_after = response["Retry-After"].presence
      message = "#{message}; retry after #{retry_after} seconds" if retry_after
      raise Error, "App Store Connect request failed (#{response.code}): #{message}"
    rescue JSON::ParserError => error
      raise Error, "App Store Connect returned invalid JSON: #{error.message}"
    end

    def credential_resolver
      @credential_resolver ||= CredentialResolver.new(
        issuer_id: setting.account_id,
        key_id: setting.external_project_name,
        credential_reference: setting.credential_reference
      )
    end
  end
end

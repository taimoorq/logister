# frozen_string_literal: true

require "net/http"
require "cgi"

module GooglePlay
  class DeveloperReportingClient
    BASE_URL = "https://playdeveloperreporting.googleapis.com"
    PAGE_SIZE = 1_000
    MAX_PAGES = 100
    Error = Class.new(StandardError)

    def initialize(credential_reference:, base_url: BASE_URL)
      @credential_reference = credential_reference
      @base_url = base_url
    end

    def release_filter_options(package_name)
      request(:get, "/v1beta1/apps/#{escape(package_name)}:fetchReleaseFilterOptions")
    end

    def anomalies(package_name)
      path = "/v1beta1/apps/#{escape(package_name)}/anomalies"
      paginate(path, collection_key: "anomalies", method: :get)
    end

    def crash_rates(package_name, start_date:, end_date:)
      metric_query(package_name, "crashRateMetricSet", %w[crashRate userPerceivedCrashRate distinctUsers], start_date:, end_date:)
    end

    def anr_rates(package_name, start_date:, end_date:)
      metric_query(package_name, "anrRateMetricSet", %w[anrRate userPerceivedAnrRate distinctUsers], start_date:, end_date:)
    end

    private

    attr_reader :credential_reference, :base_url

    def metric_query(package_name, metric_set, metrics, start_date:, end_date:)
      paginate(
        "/v1beta1/apps/#{escape(package_name)}/#{metric_set}:query",
        collection_key: "rows",
        method: :post,
        body: {
          timelineSpec: {
            aggregationPeriod: "DAILY",
            startTime: date_value(start_date),
            endTime: date_value(end_date)
          },
          dimensions: %w[versionCode],
          metrics: metrics
        }
      )
    end

    def paginate(path, collection_key:, method:, body: nil)
      rows = []
      page_token = nil

      MAX_PAGES.times do
        page_body = body&.merge(pageSize: PAGE_SIZE)
        page_body = page_body.merge(pageToken: page_token) if page_body && page_token.present?
        page_path = if method == :get
          query = { pageSize: PAGE_SIZE, pageToken: page_token }.compact.to_query
          "#{path}?#{query}"
        else
          path
        end
        page = request(method, page_path, page_body)
        rows.concat(Array(page[collection_key]))
        page_token = page["nextPageToken"].presence
        return page.except(collection_key, "nextPageToken").merge(collection_key => rows) unless page_token
      end

      raise Error, "Google Play reporting exceeded #{MAX_PAGES} pages for #{path}"
    end

    def request(method, path, body = nil)
      uri = URI.join(base_url, path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 20
      request = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{CredentialResolver.new(credential_reference).access_token}"
      request["Accept"] = "application/json"
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end
      response = http.request(request)
      payload = response.body.present? ? JSON.parse(response.body) : {}
      raise Error, "Google Play reporting request failed (#{response.code}): #{payload.dig('error', 'message') || response.message}" unless response.is_a?(Net::HTTPSuccess)

      payload
    rescue JSON::ParserError => error
      raise Error, "Google Play reporting returned invalid JSON: #{error.message}"
    end

    def date_value(date)
      value = date.to_date
      { year: value.year, month: value.month, day: value.day, timeZone: "America/Los_Angeles" }
    end

    def escape(value)
      CGI.escapeURIComponent(value.to_s)
    end
  end
end

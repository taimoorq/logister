# frozen_string_literal: true

require "set"

module GooglePlay
  class Importer
    WINDOW_DAYS = 28

    def initialize(setting, client: nil)
      @setting = setting
      @client = client || DeveloperReportingClient.new(credential_reference: setting.credential_reference)
    end

    def call
      raise ArgumentError, "Google Play setting is not configured" unless setting.configured?

      package_name = setting.external_project_id
      end_date = Date.current
      start_date = end_date - WINDOW_DAYS
      imported_at = Time.current
      release_filter_options = client.release_filter_options(package_name)
      allowed_version_codes = allowed_version_codes(release_filter_options)
      reporting = {
        "source" => "google_play_developer_reporting",
        "window" => { "start" => start_date.iso8601, "end" => end_date.iso8601, "time_zone" => "America/Los_Angeles" },
        "selected_tracks" => track_allowlist,
        "release_filter_options" => release_filter_options,
        "crash_rates" => allowed_version_rows(client.crash_rates(package_name, start_date: start_date, end_date: end_date), allowed_version_codes),
        "anr_rates" => allowed_version_rows(client.anr_rates(package_name, start_date: start_date, end_date: end_date), allowed_version_codes),
        "anomalies" => client.anomalies(package_name),
        "fetched_at" => imported_at.utc.iso8601
      }
      setting.update!(
        last_imported_at: imported_at,
        metadata: setting.metadata.merge("reporting" => reporting, "last_error" => nil)
      )
      reporting
    rescue StandardError => error
      setting.update_columns(
        metadata: setting.metadata.merge("last_error" => { "message" => error.message, "at" => Time.current.utc.iso8601 }),
        updated_at: Time.current
      ) if setting.persisted?
      raise
    end

    private

    attr_reader :setting, :client

    def track_allowlist
      @track_allowlist ||= Array(setting.metadata["track_allowlist"]).compact_blank.map(&:downcase).uniq
    end

    def allowed_version_codes(release_filter_options)
      return nil if track_allowlist.empty?

      Array(release_filter_options["tracks"]).filter_map do |track|
        next unless track_allowlist.include?(normalized_track(track))

        Array(track["servingReleases"]).flat_map { |release| Array(release["versionCodes"]) }
      end.flatten.map(&:to_s).to_set
    end

    def normalized_track(track)
      value = [ track["type"], track["displayName"] ].compact.join(" ").downcase
      return "internal" if value.include?("internal")
      return "closed" if value.include?("closed")
      return "open" if value.include?("open")
      return "production" if value.include?("production")

      value.parameterize(separator: "_")
    end

    def allowed_version_rows(payload, version_codes)
      return payload if version_codes.nil? || !payload.is_a?(Hash) || !payload["rows"].is_a?(Array)

      payload.merge(
        "rows" => payload["rows"].select do |row|
          version_codes.include?(dimension_value(row, "versionCode"))
        end
      )
    end

    def dimension_value(row, name)
      dimension = Array(row["dimensions"]).find { |value| value["dimension"] == name }
      (dimension&.[]("int64Value") || dimension&.[]("stringValue")).to_s
    end
  end
end

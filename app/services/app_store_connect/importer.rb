# frozen_string_literal: true

module AppStoreConnect
  class Importer
    def initialize(setting, client: nil)
      @setting = setting
      @client = client || Client.new(setting)
    end

    def call
      raise ArgumentError, "App Store Connect setting is not configured" unless setting.configured?

      imported_at = Time.current
      app = client.app_for_bundle_id(setting.external_project_id)
      reporting = {
        "source" => "app_store_connect_power_performance",
        "scope" => "store_aggregate",
        "app" => {
          "id" => app["id"],
          "bundle_id" => app.dig("attributes", "bundleId") || setting.external_project_id,
          "name" => app.dig("attributes", "name")
        }.compact,
        "metrics" => client.performance_metrics(app.fetch("id")),
        "fetched_at" => imported_at.utc.iso8601,
        "freshness_note" => "Apple reports require sufficient opted-in usage and can arrive days after release."
      }
      setting.update!(
        last_imported_at: imported_at,
        metadata: setting.metadata.merge("reporting" => reporting, "last_error" => nil, "last_attempted_at" => imported_at.utc.iso8601)
      )
      reporting
    rescue StandardError => error
      if setting.persisted?
        attempted_at = Time.current
        setting.update_columns(
          metadata: setting.metadata.merge(
            "last_attempted_at" => attempted_at.utc.iso8601,
            "last_error" => { "message" => error.message.to_s.first(2_000), "at" => attempted_at.utc.iso8601 }
          ),
          updated_at: attempted_at
        )
      end
      raise
    end

    private

    attr_reader :setting, :client
  end
end

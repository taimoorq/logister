# frozen_string_literal: true

module ProjectCapabilityLoaders
  class Ios < Static
    def call
      session_observed_at = correlation_observed_at
      symbol_observed_at = project.apple_symbol_artifacts.usable.maximum(:created_at)
      symbol_counts = dimension_counts("symbolication_status")
      app_store_setting = project.integration_settings.find_by(provider: ProjectIntegrationSetting::PROVIDERS.fetch(:app_store_connect))
      check_in_observed_at = project.check_in_monitors.maximum(Arel.sql("COALESCE(last_check_in_at, created_at)"))

      {
        session_health: capability_status(
          :session_health,
          session_observed_at ? :configured : :unconfigured,
          observed_at: session_observed_at,
          reason: session_observed_at ? "Session correlation evidence has been observed." : "No session correlation evidence has been observed.",
          action_key: :configure_ios_sessions
        ),
        symbol_artifacts: capability_status(
          :symbol_artifacts,
          symbol_state(symbol_observed_at, symbol_counts),
          observed_at: symbol_observed_at,
          evidence_count: symbol_counts.values.sum,
          reason: symbol_reason(symbol_observed_at, symbol_counts),
          action_key: :upload_apple_symbols
        ),
        distribution_store: distribution_status(:distribution_store, app_store_setting, label: "App Store Connect"),
        check_ins: capability_status(
          :check_ins,
          check_in_observed_at ? :configured : :unconfigured,
          observed_at: check_in_observed_at,
          reason: check_in_observed_at ? "At least one app check-in has been observed." : "No app check-in has been observed.",
          action_key: :configure_mobile_check_ins
        )
      }.freeze
    end

    private

    def symbol_state(symbol_observed_at, counts)
      address_only = counts.except("symbols_included", "not_applicable")
      return :not_applicable if counts.present? && address_only.values.sum.zero?
      return :unconfigured unless symbol_observed_at
      return :partial if address_only.empty? || address_only.any? { |status, count| status != "artifact_matched" && count.to_i.positive? }

      :configured
    end

    def symbol_reason(symbol_observed_at, counts)
      address_only = counts.except("symbols_included", "not_applicable")
      return "Observed reports already include callable symbols; no dSYM coverage is currently required." if counts.present? && address_only.values.sum.zero?
      return "No verified Apple symbol artifact is available." unless symbol_observed_at
      return "A dSYM is UUID-verified, but no address-only diagnostic has established build/binary coverage yet." if address_only.empty?
      return "Some address-only binaries are missing, blocked, or only partially covered by verified dSYMs." if address_only.any? { |status, count| status != "artifact_matched" && count.to_i.positive? }

      "Every observed address-only binary has an exact verified dSYM match. Frame symbolication is a separate state."
    end

    def dimension_counts(key)
      ErrorOccurrence.joins(:error_group)
        .where(error_groups: { project_id: project.id })
        .where("COALESCE(error_occurrences.dimensions ->> ?, '') <> ''", key)
        .group(Arel.sql("error_occurrences.dimensions ->> #{ActiveRecord::Base.connection.quote(key)}"))
        .count
    end
  end
end

# frozen_string_literal: true

module ProjectCapabilityLoaders
  class Android < Static
    def call
      session_observed_at = correlation_observed_at
      mapping_observed_at = project.android_mapping_files.maximum(:created_at)
      mapping_counts = dimension_counts("mapping_status")
      play_setting = project.integration_settings.find_by(provider: ProjectIntegrationSetting::PROVIDERS.fetch(:google_play))
      check_in_observed_at = project.check_in_monitors.maximum(Arel.sql("COALESCE(last_check_in_at, created_at)"))

      {
        session_health: capability_status(
          :session_health,
          session_observed_at ? :configured : :unconfigured,
          observed_at: session_observed_at,
          reason: session_observed_at ? "Session correlation evidence has been observed." : "No session correlation evidence has been observed.",
          action_key: :configure_android_sessions
        ),
        stack_mapping: capability_status(
          :stack_mapping,
          mapping_state(mapping_observed_at, mapping_counts),
          observed_at: mapping_observed_at,
          evidence_count: mapping_counts.values.sum,
          reason: mapping_reason(mapping_observed_at, mapping_counts),
          action_key: :upload_android_mapping
        ),
        distribution_store: distribution_status(:distribution_store, play_setting, label: "Google Play"),
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

    def mapping_state(mapping_observed_at, counts)
      return :unconfigured unless mapping_observed_at
      return :partial if counts.empty? || counts["missing"].to_i.positive? || counts["build_unknown"].to_i.positive?

      :configured
    end

    def mapping_reason(mapping_observed_at, counts)
      return "No Android mapping file has been uploaded." unless mapping_observed_at
      return "A mapping is verified, but no observed event has established build coverage yet." if counts.empty?
      return "Some observed builds are missing a matching package/version-code mapping." if counts["missing"].to_i.positive?
      return "Some observed events did not capture the version code needed for mapping coverage." if counts["build_unknown"].to_i.positive?

      "Every observed Android error build has a matching mapping artifact. Frame retracing is evaluated separately."
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

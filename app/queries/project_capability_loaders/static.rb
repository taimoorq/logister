# frozen_string_literal: true

module ProjectCapabilityLoaders
  class Static
    DISTRIBUTION_IMPORT_FRESHNESS = 1.day
    attr_reader :project

    def initialize(project)
      @project = project
    end

    def call
      {}.freeze
    end

    private

    def capability_status(key, state, observed_at: nil, evidence_count: nil, reason: nil, action_key: nil)
      CapabilityStatus.new(
        key: key,
        state: state,
        provenance: :project_evidence,
        observed_at: observed_at,
        evidence_count: evidence_count,
        reason: reason,
        action_key: action_key
      )
    end

    def correlation_observed_at
      ErrorOccurrence.joins(:error_group)
                     .where(error_groups: { project_id: project.id })
                     .where.not(session_hash: nil)
                     .maximum(:occurred_at)
    end

    def distribution_status(key, setting, label:)
      return capability_status(key, :unconfigured, reason: "#{label} reporting is not configured.", action_key: :configure_distribution_store) unless setting&.configured?

      last_error = setting.metadata.fetch("last_error", {})
      error_at = Time.zone.parse(last_error["at"].to_s) rescue nil
      if error_at && (setting.last_imported_at.nil? || error_at >= setting.last_imported_at)
        return capability_status(
          key,
          :failed,
          observed_at: error_at,
          reason: "The latest #{label} import failed. Review credentials and the bounded importer error.",
          action_key: :repair_distribution_store
        )
      end

      unless setting.last_imported_at
        return capability_status(
          key,
          :partial,
          reason: "#{label} credentials are configured, but no report has been imported successfully.",
          action_key: :import_distribution_store
        )
      end

      stale = setting.last_imported_at < DISTRIBUTION_IMPORT_FRESHNESS.ago
      capability_status(
        key,
        stale ? :stale : :configured,
        observed_at: setting.last_imported_at,
        reason: stale ? "The last successful #{label} fetch is stale; source reporting periods may be older still." : "#{label} was fetched recently; source reporting periods remain separately labelled.",
        action_key: stale ? :import_distribution_store : nil
      )
    end
  end
end

# frozen_string_literal: true

require "digest"

class ProjectInsightsCache
  SHELL_TTL = 1.minute
  CATALOG_TTL = 1.minute
  FILTER_OPTIONS_TTL = 1.minute
  DATA_TTL = 30.seconds

  class << self
    def shell(project:, endpoint:, window:)
      fetch([ "project", project.id, insights_profile(project), "insights_shell", window, bucket(SHELL_TTL) ], expires_in: SHELL_TTL) do
        insights_engine(project).shell_payload(project, endpoint:, window:)
      end
    end

    def catalog(project:, window:)
      fetch([ "project", project.id, insights_profile(project), "insights_catalog", window, bucket(CATALOG_TTL) ], expires_in: CATALOG_TTL) do
        insights_engine(project).catalog_for(project, window:)
      end
    end

    def filter_options(project:, window:)
      fetch([ "project", project.id, insights_profile(project), "insights_filter_options", window, bucket(FILTER_OPTIONS_TTL) ], expires_in: FILTER_OPTIONS_TTL) do
        insights_engine(project).filter_options(project, window:)
      end
    end

    def dashboard(project:, window:, metrics:, environment:, release:, attribute_filters:)
      dimensions = {
        metrics: Array(metrics).map(&:to_s),
        environment: environment.to_s,
        release: release.to_s,
        attributes: attribute_filters.to_h.stringify_keys.sort.to_h
      }
      fetch(
        [ "project", project.id, insights_profile(project), "insights_data", window, bucket(DATA_TTL), Digest::SHA256.hexdigest(dimensions.to_json) ],
        expires_in: DATA_TTL
      ) do
        insights_engine(project).dashboard_for(
          project,
          window:,
          metrics:,
          environment:,
          release:,
          attribute_filters:,
          catalog: catalog(project:, window:),
          filter_options: filter_options(project:, window:)
        )
      end
    end

    private

    def insights_engine(project)
      project.integration_android? || project.integration_ios? ? ProjectMobileInsights : ProjectInsights
    end

    def insights_profile(project)
      project.integration_android? || project.integration_ios? ? "mobile_v1" : "service_v1"
    end

    def fetch(key, expires_in:, &block)
      computing = false
      computed = false
      computed_value = nil
      Rails.cache.fetch(key, expires_in:, race_condition_ttl: 5.seconds) do
        computing = true
        computed_value = block.call
        computing = false
        computed = true
        computed_value
      end
    rescue StandardError => error
      raise if computing

      Rails.logger.warn("Insights cache unavailable: #{error.class} #{error.message}")
      computed ? computed_value : block.call
    end

    def bucket(ttl)
      Time.current.to_i / ttl.to_i
    end
  end
end

# frozen_string_literal: true

module ProjectExperiences
  class Android < Base
    def key
      :android
    end

    def capabilities
      @capabilities ||= begin
        values = Set.new(%i[mobile release_aware device_context structured_stacktrace])
        values << :session_health if correlation_dimensions_present?
        values << :stack_mapping if project.android_mapping_files.exists?
        values << :distribution_store if google_play_setting&.configured?
        values.freeze
      end
    end

    def inbox_title
      "Stability issues"
    end

    def inbox_empty_message
      "No Android stability issues match this view."
    end

    def search_placeholder
      "Search exceptions, methods, releases..."
    end

    def default_sort
      "recommended"
    end

    def sort_options
      [
        [ "Recommended", "recommended" ],
        [ "Impact", "impact" ],
        [ "Velocity", "velocity" ],
        [ "Newest first", "last_seen" ]
      ]
    end

    def filters
      [
        FilterDefinition.new(key: :mechanism, label: "Failure type", kind: :select, options: %w[handled_exception unhandled_exception anr native_crash low_memory_kill unknown]),
        FilterDefinition.new(key: :release, label: "Release", kind: :text, options: []),
        FilterDefinition.new(key: :build_number, label: "Build", kind: :text, options: []),
        FilterDefinition.new(key: :track, label: "Play track", kind: :select, options: %w[internal closed open production non_play]),
        FilterDefinition.new(key: :environment, label: "Environment", kind: :text, options: []),
        FilterDefinition.new(key: :build_type, label: "Build type", kind: :text, options: []),
        FilterDefinition.new(key: :device_manufacturer, label: "Manufacturer", kind: :text, options: []),
        FilterDefinition.new(key: :device_model, label: "Device", kind: :text, options: []),
        FilterDefinition.new(key: :device_form_factor, label: "Form factor", kind: :text, options: []),
        FilterDefinition.new(key: :os_version, label: "Android version", kind: :text, options: []),
        FilterDefinition.new(key: :api_level, label: "API level", kind: :text, options: []),
        FilterDefinition.new(key: :screen, label: "Screen / activity", kind: :text, options: []),
        FilterDefinition.new(key: :foreground, label: "App state", kind: :select, options: %w[true false]),
        FilterDefinition.new(key: :time_range, label: "Time range", kind: :select, options: %w[24h 7d 30d 90d all])
      ].freeze
    end

    def detail_sections(event:, occurrences_count:, related_logs_count:)
      [
        section(:stacktrace, "Stack trace"),
        section(:trail, "Trail"),
        section(:occurrences, "Occurrences (#{occurrences_count})"),
        section(:app_device, "App & device"),
        section(:raw, "Raw")
      ]
    end

    def stacktrace_partial(_event)
      "project_events/profiles/android/stacktrace"
    end

    def event_presenter(event)
      ProjectEvents::AndroidEventPresenter.new(event)
    end

    private

    def google_play_setting
      project.integration_settings.find_by(provider: ProjectIntegrationSetting::PROVIDERS[:google_play])
    end

    def correlation_dimensions_present?
      ErrorOccurrence.joins(:error_group)
                     .where(error_groups: { project_id: project.id })
                     .where.not(session_hash: nil)
                     .exists?
    end
  end
end

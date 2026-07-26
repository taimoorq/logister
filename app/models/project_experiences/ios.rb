# frozen_string_literal: true

module ProjectExperiences
  class Ios < Base
    def key
      :ios
    end

    def capabilities
      @capabilities ||= begin
        values = Set.new(%i[mobile release_aware device_context])
        values << :session_health if ErrorOccurrence.joins(:error_group)
                                                    .where(error_groups: { project_id: project.id })
                                                    .where.not(session_hash: nil)
                                                    .exists?
        values.freeze
      end
    end

    def inbox_title
      "Stability issues"
    end

    def inbox_empty_message
      "No iOS stability issues match this view."
    end

    def search_placeholder
      "Search exceptions, symbols, releases..."
    end

    def sort_options
      [ [ "Impact", "impact" ], [ "Velocity", "velocity" ], [ "Newest first", "last_seen" ] ]
    end

    def filters
      [
        FilterDefinition.new(key: :mechanism, label: "Failure type", kind: :select, options: %w[handled_exception unhandled_exception watchdog_termination native_crash low_memory_kill unknown]),
        FilterDefinition.new(key: :release, label: "Release", kind: :text, options: []),
        FilterDefinition.new(key: :build_number, label: "Build", kind: :text, options: []),
        FilterDefinition.new(key: :device_model, label: "Device", kind: :text, options: []),
        FilterDefinition.new(key: :os_version, label: "iOS version", kind: :text, options: []),
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
      "project_events/profiles/ios/stacktrace"
    end

    def event_presenter(event)
      ProjectEvents::IosEventPresenter.new(event)
    end
  end
end

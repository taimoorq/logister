# frozen_string_literal: true

require "set"

module ProjectExperiences
  class Base
    DetailSection = Data.define(:key, :label, :partial)
    FilterDefinition = Data.define(:key, :label, :kind, :options)

    DETAIL_PARTIALS = {
      context: "project_events/profiles/shared/context",
      stacktrace: "project_events/profiles/shared/stacktrace",
      occurrences: "project_events/profiles/shared/occurrences",
      related_logs: "project_events/profiles/shared/related_logs",
      trail: "project_events/profiles/mobile/trail",
      app_device: "project_events/profiles/mobile/app_device",
      raw: "project_events/profiles/shared/raw"
    }.freeze

    attr_reader :project

    def initialize(project)
      @project = project
    end

    def key
      :generic
    end

    def version
      1
    end

    def capabilities
      @capabilities ||= Set.new.freeze
    end

    def supports?(capability)
      capabilities.include?(capability.to_sym)
    end

    def inbox_title
      "Error groups"
    end

    def inbox_empty_message
      "No errors matching this filter."
    end

    def search_placeholder
      "Search errors..."
    end

    def default_sort
      "last_seen"
    end

    def sort_options
      [ [ "Newest first", "last_seen" ] ]
    end

    def filters
      [].freeze
    end

    def detail_sections(event:, occurrences_count:, related_logs_count:)
      [
        section(:context, "Context"),
        section(:stacktrace, stacktrace_tab_label(event)),
        section(:occurrences, "Occurrences (#{occurrences_count})"),
        section(:related_logs, "Related logs (#{related_logs_count})")
      ]
    end

    def normalize_detail_tab(value, event: nil, occurrences_count: 0, related_logs_count: 0)
      sections = detail_sections(
        event: event,
        occurrences_count: occurrences_count,
        related_logs_count: related_logs_count
      )
      allowed = sections.map { |section| section.key.to_s }
      value.to_s.presence_in(allowed) || default_detail_tab
    end

    def default_detail_tab
      "stacktrace"
    end

    def stacktrace_tab_label(event)
      if %w[python javascript dotnet].include?(project.integration_kind) && event&.log?
        "Details"
      else
        "Stacktrace"
      end
    end

    def stacktrace_partial(event)
      if project.integration_python? && event.log?
        "project_events/python_log_event"
      elsif project.integration_javascript? && event.log?
        "project_events/javascript_log_event"
      elsif project.integration_dotnet? && event.log?
        "project_events/dotnet_log_event"
      elsif project.integration_cfml?
        "project_events/cfml_stacktrace"
      elsif project.integration_javascript?
        "project_events/javascript_stacktrace"
      elsif project.integration_python?
        "project_events/python_stacktrace"
      elsif project.integration_dotnet?
        "project_events/dotnet_stacktrace"
      else
        "project_events/ruby_stacktrace"
      end
    end

    def event_presenter(event)
      nil
    end

    private

    def section(key, label)
      DetailSection.new(key: key, label: label, partial: DETAIL_PARTIALS.fetch(key))
    end
  end
end

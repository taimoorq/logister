# frozen_string_literal: true

require "set"

module ProjectExperiences
  class Base
    include ProjectExperiences::Detailing
    include ProjectExperiences::Setup

    DetailSection = Data.define(:key, :label, :partial)
    FilterDefinition = Data.define(:key, :label, :kind, :options)
    SetupStep = Data.define(:key, :label, :icon, :complete, :detail)

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

    private

    def section(key, label)
      DetailSection.new(key: key, label: label, partial: DETAIL_PARTIALS.fetch(key))
    end

    def setup_step(key, label, icon, complete, detail)
      SetupStep.new(key: key, label: label, icon: icon, complete: !!complete, detail: detail)
    end
  end
end

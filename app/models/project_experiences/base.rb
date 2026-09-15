# frozen_string_literal: true

require "set"

module ProjectExperiences
  class Base
    include ProjectExperiences::Detailing
    include ProjectExperiences::Setup

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
      definition.version
    end

    def definition
      @definition ||= ProjectExperience.definition_for(project.integration_kind)
    end

    def capabilities
      definition.product_capabilities
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

    def setup_step(key, label, icon, status, detail, stage: :improve_evidence, action_key: nil)
      SetupStep.new(
        key:,
        label:,
        icon:,
        state: setup_state(status),
        stage:,
        detail: status.respond_to?(:reason) && status.reason.present? ? status.reason : detail,
        action_key: status.respond_to?(:action_key) ? status.action_key : action_key
      )
    end

    def setup_state(status)
      return status ? :complete : :pending unless status.respond_to?(:state)

      {
        available: :complete,
        configured: :complete,
        partial: :partial,
        stale: :stale,
        blocked: :blocked,
        failed: :failed,
        not_applicable: :not_applicable,
        unsupported: :not_applicable,
        unconfigured: :pending
      }.fetch(status.state, :pending)
    end
  end
end

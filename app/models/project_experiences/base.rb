# frozen_string_literal: true

require "set"

module ProjectExperiences
  class Base
    include ProjectExperiences::Detailing
    include ProjectExperiences::Setup

    DetailSection = Data.define(:key, :label, :partial)
    FilterDefinition = Data.define(:key, :label, :kind, :options)
    SetupStep = Data.define(:key, :label, :icon, :state, :stage, :detail, :action_key) do
      STATES = %i[complete partial pending stale blocked failed not_applicable].freeze
      STAGES = %i[connect verify_delivery improve_evidence external_sources].freeze

      def initialize(key:, label:, icon:, state:, stage:, detail:, action_key: nil)
        raise ArgumentError, "Unknown setup state: #{state}" unless STATES.include?(state.to_sym)
        raise ArgumentError, "Unknown setup stage: #{stage}" unless STAGES.include?(stage.to_sym)

        super(key: key.to_sym, label:, icon: icon.to_sym, state: state.to_sym, stage: stage.to_sym, detail:, action_key: action_key&.to_sym)
        freeze
      end

      def complete
        %i[complete not_applicable].include?(state)
      end

      def state_label
        {
          complete: "Complete",
          partial: "Partial",
          pending: "Not verified",
          stale: "Stale",
          blocked: "Blocked",
          failed: "Failed",
          not_applicable: "Not applicable"
        }.fetch(state)
      end
    end

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

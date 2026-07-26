# frozen_string_literal: true

require "set"

module ProjectExperiences
  class Base
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

    def setup_intro
      "Start with a token, send one event, then add source and release context when the basics are flowing."
    end

    def setup_steps(status:, manager:)
      [
        setup_step(:api_key, "API key", :key, status[:active_api_key], manager ? "Create a token for the app." : "Ask an admin for a token."),
        setup_step(:first_event, "First event", :events, status[:has_events], "Send one error, log, metric, or transaction."),
        setup_step(:source_repo, "Source repo", :source_code, status[:source_repository], "Connect GitHub for source-aware frames."),
        setup_step(:deployments, "Deployments", :deployments, status[:deployments], "Record deploys from CI/CD.")
      ]
    end

    def setup_ingest_example
      {
        event: {
          event_type: "error",
          level: "error",
          message: "NoMethodError in CheckoutService",
          fingerprint: "checkout-nomethoderror",
          occurred_at: "2026-02-14T12:00:00Z",
          context: { environment: "production" }
        }
      }
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

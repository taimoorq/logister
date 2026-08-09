# frozen_string_literal: true

module ProjectActivity
  class RowPresenter
    EVENT_TYPE_LABELS = {
      "metric" => "Metric",
      "log" => "Log",
      "transaction" => "Transaction",
      "check_in" => "Check-in"
    }.freeze

    attr_reader :project, :event, :related_group

    def initialize(project:, event:, related_group: nil)
      @project = project
      @event = event
      @related_group = related_group
    end

    def self.trace_id(event)
      context = event.context.is_a?(Hash) ? event.context.stringify_keys : {}
      context["trace_id"].to_s.presence || context.dig("trace", "id").to_s.presence
    end

    def event_type_label
      EVENT_TYPE_LABELS.fetch(event.event_type, event.event_type.humanize)
    end

    def headline
      event.message.to_s.lines.first.to_s.strip.presence || "Untitled #{event_type_label.downcase}"
    end

    def source_label
      if profile.key == :ios && event_presenter.respond_to?(:diagnostic_source_label)
        reported = event_presenter.diagnostic_source_label
        reported == "Source not reported" ? source_fallback_label : reported
      elsif profile.key == :android && event_presenter.respond_to?(:capture_source_label)
        event_presenter.capture_source_label.presence || source_fallback_label
      else
        source_fallback_label
      end
    end

    def time_precision_label
      {
        "exact" => "Exact occurrence",
        "reporting_interval" => "Reporting interval",
        "received_only" => "Receipt time only",
        "unknown" => "Legacy time"
      }.fetch(evidence.time_precision, "Time not classified")
    end

    def time_label
      if evidence.exact_time?
        "Occurred #{relative_time(evidence.occurred_at || event.occurred_at)} ago"
      elsif evidence.reporting_interval?
        boundary = evidence.reporting_end || evidence.reporting_start
        boundary ? "Reported through #{relative_time(boundary)} ago" : "Reporting interval"
      elsif evidence.received_only?
        "Received #{relative_time(evidence.received_at || event.created_at)} ago"
      else
        "Occurred #{relative_time(event.occurred_at)} ago"
      end
    end

    def time_title
      values = []
      values << "Occurred #{formatted_time(evidence.occurred_at || event.occurred_at)}" if evidence.exact_time? || evidence.time_precision == "unknown"
      if evidence.reporting_interval?
        values << "Reporting interval #{formatted_time(evidence.reporting_start) || 'unknown'} to #{formatted_time(evidence.reporting_end) || 'unknown'}"
      end
      values << "Received #{formatted_time(evidence.received_at || event.created_at)}"
      values.join(". ")
    end

    def app_release_label
      app = event_presenter.app_details
      version = [ app[:version_name], app[:version_code].presence && "(#{app[:version_code]})" ].compact_blank.join(" ").presence
      release = normalized_context["release"].to_s.split("@").last.to_s.presence
      [ version || release, app[:track] || app[:distribution_channel] ].compact_blank.join(" · ").presence
    end

    def component_label
      app = event_presenter.app_details
      values = [
        app[:process],
        app[:screen],
        normalized_context["component"],
        normalized_context["transaction_name"],
        normalized_context["name"],
        normalized_context["logger_name"],
        normalized_context["check_in_slug"]
      ]
      values.compact_blank.map(&:to_s).uniq.first(3).join(" · ").presence
    end

    def trace_correlated?
      self.class.trace_id(event).present?
    end

    def related_issue_label
      "Related issue: #{related_group.title}" if related_group
    end

    private

    def source_fallback_label
      {
        "sdk" => "Logister SDK",
        "metrickit" => "MetricKit",
        "app_store" => "App Store Connect",
        "google_play" => "Google Play",
        "api" => "API"
      }.fetch(evidence.source.to_s, evidence.source.to_s.humanize)
    end

    def profile
      @profile ||= ProjectExperience.for(project)
    end

    def event_presenter
      @event_presenter ||= profile.event_presenter(event)
    end

    def evidence
      @evidence ||= TelemetryEvidence.for(event)
    end

    def normalized_context
      @normalized_context ||= MobileTelemetryNormalizer.normalize(event.context)
    end

    def relative_time(time)
      return "at an unknown time" unless time

      ActionController::Base.helpers.time_ago_in_words(time)
    end

    def formatted_time(time)
      I18n.l(time, format: :long) if time
    end
  end
end

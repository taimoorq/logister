# frozen_string_literal: true

module ProjectInbox
  class RowPresenter
    attr_reader :project, :group, :event, :trend, :impact, :mapping_resolution, :symbol_coverage, :evidence_signal

    def initialize(project:, group:, event:, trend: [], impact: nil, mapping_resolution: nil, symbol_coverage: nil, evidence_signal: nil)
      @project = project
      @group = group
      @event = event
      @trend = trend
      @impact = impact
      @mapping_resolution = mapping_resolution
      @symbol_coverage = symbol_coverage
      @evidence_signal = evidence_signal
    end

    def profile
      @profile ||= ProjectExperience.for(project)
    end

    def android?
      profile.key == :android && event.present?
    end

    def mobile?
      profile.supports?(:mobile) && event.present?
    end

    def event_presenter
      @event_presenter ||= if profile.key == :ios
        ProjectEvents::IosEventPresenter.new(event, enrichment: symbol_coverage&.enrichment)
      else
        profile.event_presenter(event)
      end
    end

    def evidence
      @evidence ||= TelemetryEvidence.for(event)
    end

    def attention_signal
      return "Regressed" if regression_presenter.present?
      return "New" if group.created_at && group.created_at >= 24.hours.ago

      evidence_signal&.label
    end

    def attention_detail_label
      return regression_presenter.concise_label if attention_signal == "Regressed"

      evidence_signal&.concise_label
    end

    def attention_title
      return regression_presenter.title if attention_signal == "Regressed"

      evidence_signal&.title
    end

    def failure_type_label
      return unless mobile?

      event_presenter.respond_to?(:failure_type_label) ? event_presenter.failure_type_label : event_presenter.mechanism_label
    end

    def fatality_label
      return unless mobile?

      label = { "fatal" => "Fatal", "nonfatal" => "Nonfatal" }[evidence.fatality]
      label unless label.present? && failure_type_label.to_s.casecmp?(label)
    end

    def workflow_label
      {
        "unresolved" => "Open",
        "resolved" => "Resolved",
        "ignored" => "Muted",
        "archived" => "Archived"
      }.fetch(group.status.to_s, group.status.to_s.humanize)
    end

    def signal_labels
      labels = [ attention_signal ]
      labels << failure_type_label if mobile?
      labels.compact_blank.presence || [ group.status.humanize ]
    end

    def headline
      return group.title unless mobile?

      if android? && mapped_android_frame
        type = mapping_resolution.cause_chain.last&.dig(:type).presence || event_presenter.exception_type
        method = mapped_android_frame[:qualified_method].presence || mapped_android_frame[:method_name]
        return [ type, method.present? && "in #{method}" ].compact_blank.join(" ")
      end

      if event_presenter.respond_to?(:technical_signature)
        event_presenter.technical_signature.presence || group.title
      else
        group.title
      end
    end

    def culprit
      return group.subtitle unless mobile?

      frame = event_presenter.top_in_app_frame
      return group.subtitle if frame.blank?

      location = frame[:file].presence
      location = "#{location}:#{frame[:line_number]}" if location && frame[:line_number]
      [ frame[:qualified_method].presence || frame[:method_name], location ].compact_blank.join(" · ")
    end

    def supporting_label
      return group.subtitle unless mobile?

      location = mapped_android_location
      location ||= event_presenter.culprit_location if event_presenter.respond_to?(:culprit_location)
      [ location, release_label, source_label ].compact_blank.join(" · ").presence || group.subtitle
    end

    def artifact_quality_label
      if android? && mapping_resolution
        return if %i[mapped mapping_matched].include?(mapping_resolution.status)

        mapping_resolution.label
      elsif profile.key == :ios && symbol_coverage
        return if %i[symbolicated symbols_included artifact_matched not_applicable].include?(symbol_coverage.status)

        symbol_coverage.label
      end
    end

    def source_label
      return unless mobile?
      return event_presenter.diagnostic_source_label if profile.key == :ios

      event_presenter.capture_source_label.presence || evidence.source.to_s.humanize.presence
    end

    def release_label
      return unless mobile?

      app = event_presenter.app_details
      version = formatted_release(impact&.last_release)
      version ||= [ app[:version_name], app[:version_code].presence && "(#{app[:version_code]})" ].compact.join(" ")
      [ version.presence, app[:track] || app[:distribution_channel] ].compact_blank.join(" · ").presence
    end

    def cohort_label
      return unless mobile?

      device = event_presenter.device_details
      os = event_presenter.os_details
      [ device[:model], os[:version].presence && "#{os[:name].presence || project.integration_kind.upcase_first} #{os[:version]}", os[:api_level].presence && "API #{os[:api_level]}" ].compact_blank.join(" · ").presence
    end

    def occurrence_label
      "#{group.occurrence_count} #{'event'.pluralize(group.occurrence_count)}"
    end

    def impact_label
      return unless mobile? && impact

      if impact.installations.available?
        "#{impact.installations.value} #{'installation'.pluralize(impact.installations.value)}"
      elsif impact.sessions.available?
        "#{impact.sessions.value} #{'session'.pluralize(impact.sessions.value)}"
      end
    end

    def impact_coverage_label
      return unless mobile? && impact

      metric = if impact.installations.available?
        impact.installations
      elsif impact.sessions.available?
        impact.sessions
      end
      return unless metric

      {
        complete: "complete coverage",
        partial: "partial coverage",
        sampled: "sampled coverage"
      }[metric.state]
    end

    def evidence_quality_label
      return unless mobile?

      {
        "exact" => nil,
        "reporting_interval" => "Reporting interval",
        "received_only" => "Receipt time only",
        "unknown" => "Legacy time"
      }.fetch(evidence.time_precision, "Time not classified")
    end

    def recency_label
      return unless mobile?

      if evidence.exact_time?
        "occurred #{relative_time(evidence.occurred_at || event.occurred_at)} ago"
      elsif evidence.reporting_interval?
        boundary = evidence.reporting_end || evidence.reporting_start
        boundary ? "reported through #{relative_time(boundary)} ago" : "reporting interval received #{relative_time(evidence.received_at || event.created_at)} ago"
      elsif evidence.received_only?
        "received #{relative_time(evidence.received_at || event.created_at)} ago"
      else
        "last seen #{relative_time(event.occurred_at)} ago"
      end
    end

    def recency_title
      return unless mobile?

      values = []
      values << "Occurred #{formatted_time(evidence.occurred_at)}" if evidence.occurred_at
      if evidence.reporting_start || evidence.reporting_end
        values << "Reporting interval #{formatted_time(evidence.reporting_start) || 'unknown'} to #{formatted_time(evidence.reporting_end) || 'unknown'}"
      end
      values << "Received #{formatted_time(evidence.received_at || event.created_at)}" if evidence.received_at || event.respond_to?(:created_at)
      values.join(". ")
    end

    def accessibility_label
      return "Open error details for #{group.title}" unless mobile?

      [
        attention_signal,
        attention_detail_label,
        failure_type_label,
        fatality_label,
        headline,
        impact_label,
        impact_coverage_label,
        recency_label,
        workflow_label,
        "Button"
      ].compact_blank.join(", ")
    end

    private

    def regression_presenter
      @regression_presenter ||= ErrorGroupRegressionPresenter.new(group)
    end

    def formatted_release(value)
      release = value.to_s.split("@").last.to_s
      version, separator, build = release.rpartition("+")
      return unless release.present?
      return release if separator.blank? || version.blank? || build.blank?

      "#{version} (#{build})"
    end

    def mapped_android_frame
      return unless android? && mapping_resolution

      mapping_resolution.frames.find { |frame| frame[:application_frame] } || mapping_resolution.frames.first
    end

    def mapped_android_location
      frame = mapped_android_frame
      return unless frame

      location = frame[:file].presence
      location = "#{location}:#{frame[:line_number]}" if location && frame[:line_number]
      location
    end

    def relative_time(time)
      return "an unknown time" unless time

      ActionController::Base.helpers.time_ago_in_words(time)
    end

    def formatted_time(time)
      I18n.l(time, format: :long) if time
    end
  end
end

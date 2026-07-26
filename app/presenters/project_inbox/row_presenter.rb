# frozen_string_literal: true

module ProjectInbox
  class RowPresenter
    attr_reader :project, :group, :event, :trend, :impact

    def initialize(project:, group:, event:, trend: [], impact: nil)
      @project = project
      @group = group
      @event = event
      @trend = trend
      @impact = impact
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
      @event_presenter ||= profile.event_presenter(event)
    end

    def signal_labels
      labels = []
      labels << "Regressed" if group.regression_count.to_i.positive?
      labels << "New" if group.first_seen_at && group.first_seen_at >= 24.hours.ago
      labels << event_presenter.mechanism_label if mobile?
      labels.presence || [ group.status.humanize ]
    end

    def culprit
      return group.subtitle unless mobile?

      frame = event_presenter.top_in_app_frame
      return group.subtitle if frame.blank?

      location = frame[:file].presence
      location = "#{location}:#{frame[:line_number]}" if location && frame[:line_number]
      [ frame[:qualified_method].presence || frame[:method_name], location ].compact_blank.join(" · ")
    end

    def release_label
      return unless mobile?

      app = event_presenter.app_details
      version = [ app[:version_name], app[:version_code].presence && "(#{app[:version_code]})" ].compact.join(" ")
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
  end
end

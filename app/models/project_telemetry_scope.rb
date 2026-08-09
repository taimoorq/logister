# frozen_string_literal: true

class ProjectTelemetryScope
  WINDOWS = %w[1h 6h 24h 7d 30d 90d all].freeze
  ACTIVITY_WINDOWS = %w[24h 7d 30d 90d all].freeze
  INSIGHTS_WINDOWS = %w[1h 6h 24h 7d].freeze
  INBOX_WINDOWS = %w[24h 7d 30d 90d all].freeze
  FIELDS = %i[window environment release build_number distribution source platform].freeze

  Projection = Data.define(:page, :params, :dropped) do
    def dropped?
      dropped.any?
    end
  end

  attr_reader :project, *FIELDS

  def self.from(project:, source:)
    values = source.respond_to?(:to_unsafe_h) ? source.to_unsafe_h : source.to_h
    values = values.deep_stringify_keys
    attributes = values["attributes"].is_a?(Hash) ? values["attributes"] : {}
    new(
      project:,
      window: first(values["window"], values["time_range"], values["period"]),
      environment: values["environment"],
      release: values["release"],
      build_number: first(values["build_number"], attributes["build_number"]),
      distribution: first(values["distribution"], values["channel"], values["distribution_channel"], values["track"], attributes["distribution_channel"]),
      source: first(values["source"], values["diagnostic_source"], attributes["evidence_source"]),
      platform: first(values["platform"], values["apple_platform"], attributes["platform"])
    )
  end

  def self.first(*values)
    values.find(&:present?)
  end

  def initialize(project:, window: nil, environment: nil, release: nil, build_number: nil, distribution: nil, source: nil, platform: nil)
    @project = project
    @window = normalize_window(window)
    @environment = normalize_value(environment)
    @release = normalize_value(release)
    @build_number = mobile? ? normalize_value(build_number) : nil
    @distribution = mobile? ? normalize_value(distribution)&.downcase : nil
    @source = mobile? ? normalize_value(source)&.downcase : nil
    @platform = mobile? ? normalize_value(platform)&.downcase : nil
    freeze
  end

  def project_for(page)
    send("project_for_#{page}")
  end

  def to_h
    FIELDS.index_with { |field| public_send(field) }.compact
  end

  private

  def project_for_activity
    supported = %i[window environment release build_number distribution source platform]
    params = {
      period: window.presence_in(ACTIVITY_WINDOWS),
      environment:,
      release:,
      build_number:,
      channel: distribution,
      source:,
      platform:
    }.compact
    projection(:activity, supported, params, window_supported: ACTIVITY_WINDOWS)
  end

  def project_for_insights
    supported = %i[window environment release build_number distribution source platform]
    attributes = {
      build_number:,
      distribution_channel: distribution,
      evidence_source: source,
      platform:
    }.compact
    params = {
      window: window.presence_in(INSIGHTS_WINDOWS),
      environment:,
      release:,
      attributes: attributes.presence
    }.compact
    projection(:insights, supported, params, window_supported: INSIGHTS_WINDOWS)
  end

  def project_for_inbox
    supported = %i[window environment release build_number distribution source platform]
    params = {
      time_range: window.presence_in(INBOX_WINDOWS),
      environment:,
      release:,
      build_number:,
      diagnostic_source: (source if project.integration_ios?),
      track: (distribution if project.integration_android?),
      distribution_channel: (distribution if project.integration_ios?),
      apple_platform: (platform if project.integration_ios?)
    }.compact
    projection(:inbox, supported, params, window_supported: INBOX_WINDOWS)
  end

  def projection(page, supported, params, window_supported:)
    dropped = to_h.keys.reject { |key| supported.include?(key) }
    dropped << :window if window.present? && !window_supported.include?(window)
    Projection.new(page:, params: params.freeze, dropped: dropped.uniq.freeze).freeze
  end

  def mobile?
    project.integration_android? || project.integration_ios?
  end

  def normalize_window(value)
    value.to_s.presence_in(WINDOWS)
  end

  def normalize_value(value)
    value.to_s.strip.first(100).presence
  end
end

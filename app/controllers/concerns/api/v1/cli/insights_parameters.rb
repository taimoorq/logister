# frozen_string_literal: true

module Api::V1::Cli::InsightsParameters
  extend ActiveSupport::Concern

  private

  def cli_insights_window
    Logister::CliQuery.enum(
      params[:window].presence || ProjectInsights::DEFAULT_WINDOW,
      parameter: "window",
      allowed: ProjectInsights::WINDOW_OPTIONS.keys
    )
  end

  def cli_insights_attributes
    values = raw_attribute_hash
    Array(params[:attribute]).each do |entry|
      key, value = entry.to_s.split("=", 2)
      if key.blank? || value.blank?
        raise Logister::CliQuery::InvalidParameter.new("attribute must use key=value", parameter: "attribute")
      end
      values[key] = value
    end
    if values.length > ProjectInsights::MAX_ATTRIBUTE_FILTERS
      raise Logister::CliQuery::InvalidParameter.new(
        "attribute supports at most #{ProjectInsights::MAX_ATTRIBUTE_FILTERS} filters",
        parameter: "attribute"
      )
    end

    values.to_h do |key, value|
      normalized_key = key.to_s.strip
      unless normalized_key.match?(ProjectInsights::ATTRIBUTE_KEY_PATTERN) && !Logister::TelemetryRedactor.sensitive_key?(normalized_key)
        raise Logister::CliQuery::InvalidParameter.new("attribute contains an unsupported key", parameter: "attribute")
      end
      normalized_value = Logister::CliQuery.text(value, parameter: "attribute", max: ProjectInsights::MAX_FILTER_LENGTH)
      [ normalized_key, normalized_value ]
    end
  end

  def validate_cli_insights_attributes!(project:, window:, attributes:)
    return if attributes.empty?

    catalog = ProjectInsightsCache.filter_options(project:, window:).fetch(:attributes)
    catalog_by_key = catalog.index_by { |attribute| attribute.fetch(:key) }
    attributes.each do |key, value|
      attribute = catalog_by_key[key]
      valid = attribute&.fetch(:values, [])&.any? { |option| option.fetch(:name).to_s == value.to_s }
      next if valid

      raise Logister::CliQuery::InvalidParameter.new("attribute is unknown for this project and window", parameter: "attribute")
    end
  end

  def cli_metrics
    (Array(params[:metric]) + Array(params[:metrics])).map(&:to_s).map(&:strip).reject(&:blank?).uniq
  end

  def validate_cli_metrics!(project:, window:, metrics:, required: false)
    if required && metrics.empty?
      raise Logister::CliQuery::InvalidParameter.new("metric is required", parameter: "metric")
    end
    if metrics.length > ProjectInsights::MAX_SELECTED_METRICS
      raise Logister::CliQuery::InvalidParameter.new(
        "metric supports at most #{ProjectInsights::MAX_SELECTED_METRICS} values",
        parameter: "metric"
      )
    end

    available = ProjectInsightsCache.catalog(project:, window:).pluck(:key)
    unknown = metrics - available
    return if unknown.empty?

    raise Logister::CliQuery::InvalidParameter.new("unknown metric: #{unknown.join(', ')}", parameter: "metric")
  end

  def raw_attribute_hash
    raw = params[:attributes]
    if raw.respond_to?(:to_unsafe_h)
      raw.to_unsafe_h
    elsif raw.respond_to?(:to_h)
      raw.to_h
    else
      {}
    end.stringify_keys
  end

  def safe_cli_analytics(value)
    analytics = value.to_h.stringify_keys
    coverage = analytics["coverage"].to_h.stringify_keys
    {
      source: analytics["source"],
      coverage: coverage.present? && {
        complete: coverage["complete"],
        ratio: coverage["coverage_ratio"],
        fresh_through: coverage["fresh_through"]
      },
      partial: false
    }.compact
  end
end

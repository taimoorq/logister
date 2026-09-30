# frozen_string_literal: true

class ProjectPageCatalog
  BASE_ATTRIBUTES = BasePages::ATTRIBUTES

  # Mobile projects keep the shared sections. Only the evidence vocabulary and a
  # few extra Releases views differ.
  MOBILE_OVERRIDES = {
    inbox: {
      description: "Crashes, hangs, terminations, and reported errors"
    }.freeze,
    activity: {
      description: "Non-error telemetry and app activity"
    }.freeze,
    performance: {
      header_label: "Project app health",
      description: "Responsiveness, resource use, and app-supplied performance"
    }.freeze,
    monitors: {
      description: "Background work and heartbeat status"
    }.freeze,
    deployments: {
      view_label: "Deploy records",
      description: "Deploy records reported by CI alongside observed app builds"
    }.freeze
  }.freeze

  MOBILE_PAGES = [
    {
      key: :releases,
      route_key: :releases,
      section_key: :releases,
      view_label: "Releases",
      label: "Releases",
      header_label: "Project releases",
      description: "Observed app builds, channels, stability, and artifact coverage",
      icon_key: :deployments,
      order: 39
    }.freeze,
    {
      key: :artifacts,
      route_key: :artifacts,
      section_key: :releases,
      view_label: "Artifacts",
      label: "Artifacts",
      header_label: "Project artifacts",
      description: "Build artifacts and observed-build coverage",
      icon_key: :source_code,
      order: 40
    }.freeze
  ].freeze

  PAGE_BUILDER = lambda do |overrides = {}, additions = []|
    (BASE_ATTRIBUTES + additions).map do |attributes|
      replacement = overrides.fetch(attributes.fetch(:key), {})
      ProjectPageDefinition.new(**attributes.merge(replacement)).freeze
    end.freeze
  end
  private_constant :PAGE_BUILDER

  PAGES_BY_EXPERIENCE = {
    server: PAGE_BUILDER.call,
    edge: PAGE_BUILDER.call,
    android: PAGE_BUILDER.call(MOBILE_OVERRIDES, MOBILE_PAGES),
    ios: PAGE_BUILDER.call(MOBILE_OVERRIDES, MOBILE_PAGES),
    custom: PAGE_BUILDER.call
  }.freeze

  class << self
    def fetch(experience_key)
      PAGES_BY_EXPERIENCE.fetch(experience_key.to_sym)
    end

    def validate!(experience_key)
      pages = fetch(experience_key)
      duplicate_keys = pages.map(&:key).tally.select { |_key, count| count > 1 }.keys
      duplicate_orders = pages.map(&:order).tally.select { |_order, count| count > 1 }.keys

      raise ArgumentError, "Duplicate project page keys for #{experience_key}: #{duplicate_keys.join(', ')}" if duplicate_keys.any?
      raise ArgumentError, "Duplicate project page orders for #{experience_key}: #{duplicate_orders.join(', ')}" if duplicate_orders.any?

      pages.each do |page|
        raise ArgumentError, "Project page #{page.key} has an unknown section" unless ProjectNavSection.key?(page.section_key)
        if page.route_key
          ProjectPageRoutes.validate!(page.route_key)
        elsif !page.hidden?
          raise ArgumentError, "Navigable project page #{page.key} must have a route"
        end
        raise ArgumentError, "Hidden project page #{page.key} cannot be a section view" if page.hidden? && page.view_label.present?
      end

      missing = ProjectNavSection::ALL.reject { |section| pages.any? { |page| page.section_key == section.key && !page.hidden? } }
      raise ArgumentError, "Project sections without a navigable page for #{experience_key}: #{missing.map(&:key).join(', ')}" if missing.any?

      true
    end
  end
end

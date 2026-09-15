# frozen_string_literal: true

class ProjectPageCatalog
  BASE_ATTRIBUTES = BasePages::ATTRIBUTES

  MOBILE_OVERRIDES = {
    inbox: {
      label: "Stability",
      header_label: "Project stability",
      description: "Crashes, hangs, terminations, and reported errors"
    }.freeze,
    activity: {
      label: "Activity",
      header_label: "Project activity",
      description: "Non-error telemetry and app activity"
    }.freeze,
    performance: {
      label: "App health",
      header_label: "Project app health",
      description: "Responsiveness, resource use, and app-supplied performance"
    }.freeze,
    monitors: {
      label: "Check-ins",
      header_label: "Project check-ins",
      description: "Background work and heartbeat status",
      navigation_group: :secondary,
      menu_group: "Project tools",
      order: 65
    }.freeze
  }.freeze

  MOBILE_PAGES = [
    {
      key: :releases,
      route_key: :releases,
      active_parent_key: nil,
      label: "Releases",
      header_label: "Project releases",
      description: "Observed app builds, channels, stability, and artifact coverage",
      icon_key: :deployments,
      navigation_group: :primary,
      menu_group: nil,
      order: 55,
      core: true
    }.freeze,
    {
      key: :artifacts,
      route_key: :artifacts,
      active_parent_key: nil,
      label: "Artifacts",
      header_label: "Project artifacts",
      description: "Build artifacts and observed-build coverage",
      icon_key: :source_code,
      navigation_group: :secondary,
      menu_group: "Build & source",
      order: 75,
      core: true
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
        raise ArgumentError, "Project page #{page.key} has an unknown navigation group" unless ProjectPageDefinition::NAVIGATION_GROUPS.include?(page.navigation_group)
        if page.route_key
          ProjectPageRoutes.validate!(page.route_key)
        elsif !page.hidden?
          raise ArgumentError, "Navigable project page #{page.key} must have a route"
        end
        next if page.active_parent_key.nil? || pages.any? { |candidate| candidate.key == page.active_parent_key }

        raise ArgumentError, "Project page #{page.key} references an unknown active parent"
      end

      true
    end
  end
end

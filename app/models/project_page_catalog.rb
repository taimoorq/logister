# frozen_string_literal: true

class ProjectPageCatalog
  BASE_ATTRIBUTES = [
    {
      key: :overview,
      route_key: :overview,
      active_parent_key: nil,
      label: "Overview",
      header_label: "Project overview",
      description: "At-a-glance health and recent signals",
      icon_key: :home,
      navigation_group: :primary,
      menu_group: nil,
      order: 10,
      core: true
    }.freeze,
    {
      key: :inbox,
      route_key: :inbox,
      active_parent_key: nil,
      label: "Inbox",
      header_label: "Project inbox",
      description: "Errors that need triage",
      icon_key: :inbox,
      navigation_group: :primary,
      menu_group: nil,
      order: 20,
      core: true
    }.freeze,
    {
      key: :activity,
      route_key: :activity,
      active_parent_key: nil,
      label: "Events",
      header_label: "Project events",
      description: "Logs, metrics, transactions, and check-ins",
      icon_key: :events,
      navigation_group: :primary,
      menu_group: nil,
      order: 30,
      core: true
    }.freeze,
    {
      key: :insights,
      route_key: :insights,
      active_parent_key: nil,
      label: "Insights",
      header_label: "Project insights",
      description: "Trends and deeper telemetry exploration",
      icon_key: :insights,
      navigation_group: :primary,
      menu_group: nil,
      order: 40,
      core: true
    }.freeze,
    {
      key: :performance,
      route_key: :performance,
      active_parent_key: nil,
      label: "Performance",
      header_label: "Project performance",
      description: "Slow or failing requests and jobs",
      icon_key: :performance,
      navigation_group: :primary,
      menu_group: nil,
      order: 50,
      core: true
    }.freeze,
    {
      key: :monitors,
      route_key: :monitors,
      active_parent_key: nil,
      label: "Monitors",
      header_label: "Project monitors",
      description: "Scheduled jobs and heartbeat status",
      icon_key: :monitors,
      navigation_group: :primary,
      menu_group: nil,
      order: 60,
      core: false
    }.freeze,
    {
      key: :deployments,
      route_key: :deployments,
      active_parent_key: nil,
      label: "Deployments",
      header_label: "Project deployments",
      description: "Releases, commits, and deploy metadata",
      icon_key: :deployments,
      navigation_group: :secondary,
      menu_group: "Project tools",
      order: 70,
      core: false
    }.freeze,
    {
      key: :archives,
      route_key: :archives,
      active_parent_key: nil,
      label: "Archive search",
      header_label: "Project archive search",
      description: "Find current and archived telemetry",
      icon_key: :archive,
      navigation_group: :secondary,
      menu_group: "Project tools",
      order: 80,
      core: false
    }.freeze,
    {
      key: :settings,
      route_key: :settings,
      active_parent_key: nil,
      label: "Settings",
      header_label: "Project settings",
      description: "Setup, access, integrations, and project preferences",
      icon_key: :settings,
      navigation_group: :secondary,
      menu_group: "Manage",
      order: 90,
      core: true
    }.freeze,
    {
      key: :setup,
      route_key: :setup,
      active_parent_key: :settings,
      label: "Setup",
      header_label: "Project setup",
      description: "Connect and verify project telemetry",
      icon_key: :settings,
      navigation_group: :hidden,
      menu_group: nil,
      order: 91,
      core: true
    }.freeze,
    {
      key: :edit,
      route_key: :edit,
      active_parent_key: :settings,
      label: "Edit project",
      header_label: "Project settings",
      description: "Edit project identity",
      icon_key: :settings,
      navigation_group: :hidden,
      menu_group: nil,
      order: 92,
      core: true
    }.freeze,
    {
      key: :error_event,
      route_key: nil,
      active_parent_key: :inbox,
      label: "Issue detail",
      header_label: "Project issue",
      description: "Inspect one grouped error occurrence",
      icon_key: :inbox,
      navigation_group: :hidden,
      menu_group: nil,
      order: 93,
      core: true
    }.freeze,
    {
      key: :activity_event,
      route_key: nil,
      active_parent_key: :activity,
      label: "Event detail",
      header_label: "Project event",
      description: "Inspect one telemetry event",
      icon_key: :events,
      navigation_group: :hidden,
      menu_group: nil,
      order: 94,
      core: true
    }.freeze
  ].freeze

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
      description: "Background work and heartbeat status"
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
      description: "R8 mappings or dSYMs and observed-build coverage",
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

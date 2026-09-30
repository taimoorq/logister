# frozen_string_literal: true

module ProjectPageCatalog::BasePages
  ATTRIBUTES = [
    {
      key: :overview,
      route_key: :overview,
      section_key: :overview,
      label: "Overview",
      header_label: "Project overview",
      description: "At-a-glance health and recent signals",
      icon_key: :home,
      order: 10
    }.freeze,
    {
      key: :inbox,
      route_key: :inbox,
      section_key: :issues,
      label: "Issues",
      header_label: "Project issues",
      description: "Errors that need triage",
      icon_key: :inbox,
      order: 20
    }.freeze,
    {
      key: :error_event,
      route_key: nil,
      section_key: :issues,
      label: "Issue detail",
      header_label: "Project issue",
      description: "Inspect one grouped error occurrence",
      icon_key: :inbox,
      hidden: true,
      parent_key: :inbox,
      order: 21
    }.freeze,
    {
      key: :performance,
      route_key: :performance,
      section_key: :performance,
      label: "Performance",
      header_label: "Project performance",
      description: "Slow or failing requests and jobs",
      icon_key: :performance,
      order: 30
    }.freeze,
    {
      key: :deployments,
      route_key: :deployments,
      section_key: :releases,
      view_label: "Deployments",
      label: "Deployments",
      header_label: "Project deployments",
      description: "Releases, commits, and deploy metadata",
      icon_key: :deployments,
      order: 41
    }.freeze,
    {
      key: :activity,
      route_key: :activity,
      section_key: :explore,
      view_label: "Events",
      label: "Events",
      header_label: "Project events",
      description: "Logs, metrics, transactions, and check-ins",
      icon_key: :events,
      order: 50
    }.freeze,
    {
      key: :insights,
      route_key: :insights,
      section_key: :explore,
      view_label: "Charts",
      label: "Charts",
      header_label: "Project charts",
      description: "Trends and deeper telemetry exploration",
      icon_key: :insights,
      order: 51
    }.freeze,
    {
      key: :archives,
      route_key: :archives,
      section_key: :explore,
      view_label: "Archive",
      label: "Archive",
      header_label: "Project archive",
      description: "Find current and archived telemetry",
      icon_key: :archive,
      order: 52
    }.freeze,
    {
      key: :connections,
      route_key: :connections,
      section_key: :explore,
      view_label: "Connected",
      label: "Connected",
      header_label: "Connected impact",
      description: "Related issues, request timing, and releases across linked projects",
      icon_key: :integrations,
      order: 53
    }.freeze,
    {
      key: :activity_event,
      route_key: nil,
      section_key: :explore,
      label: "Event detail",
      header_label: "Project event",
      description: "Inspect one telemetry event",
      icon_key: :events,
      hidden: true,
      parent_key: :activity,
      order: 54
    }.freeze,
    {
      key: :correlations,
      route_key: nil,
      section_key: :explore,
      label: "Related requests",
      header_label: "Connected impact",
      description: "Follow one request across linked projects",
      icon_key: :integrations,
      hidden: true,
      parent_key: :connections,
      order: 55
    }.freeze,
    {
      key: :monitors,
      route_key: :monitors,
      section_key: :monitors,
      label: "Monitors",
      header_label: "Project monitors",
      description: "Scheduled jobs and heartbeat status",
      icon_key: :monitors,
      order: 60
    }.freeze,
    {
      key: :settings,
      route_key: :settings,
      section_key: :settings,
      label: "Settings",
      header_label: "Project settings",
      description: "Setup, access, integrations, and project preferences",
      icon_key: :settings,
      order: 90
    }.freeze,
    {
      key: :setup,
      route_key: :setup,
      section_key: :settings,
      label: "Setup",
      header_label: "Project setup",
      description: "Connect and verify project telemetry",
      icon_key: :setup,
      hidden: true,
      parent_key: :settings,
      order: 91
    }.freeze,
    {
      key: :project_links,
      route_key: :project_links,
      section_key: :settings,
      label: "Connections",
      header_label: "Connected projects",
      description: "Link apps and backends so requests can be followed between them",
      icon_key: :integrations,
      hidden: true,
      parent_key: :settings,
      order: 93
    }.freeze
  ].freeze
end

# frozen_string_literal: true

module ProjectInboxData
  extend ActiveSupport::Concern

  INBOX_FILTERS = ProjectInboxQuery::FILTERS
  INBOX_LIMIT = ProjectInboxQuery::LIMIT

  private

  def inbox_groups(project, filter:, query: nil, assignee: "all", viewer: nil, dimensions: {}, sort: nil)
    project_inbox_query(project, viewer: viewer).groups(
      filter: filter,
      query: query,
      assignee: assignee,
      dimensions: dimensions,
      sort: sort
    )
  end

  def inbox_page(project, filter:, query: nil, assignee: "all", viewer: nil, dimensions: {}, sort: nil, cursor: nil)
    project_inbox_query(project, viewer: viewer).page(
      filter: filter,
      query: query,
      assignee: assignee,
      dimensions: dimensions,
      sort: sort,
      cursor: cursor
    )
  end

  def inbox_latest_events(project, groups, profile_filters: {})
    return {} if groups.empty?

    project_inbox_query(project).latest_events(groups, dimensions: profile_filters)
  end

  def inbox_group_trends(project, groups, days: nil, profile_filters: {})
    range = profile_filters.to_h.stringify_keys["time_range"]
    days ||= { "24h" => 1, "7d" => 7, "30d" => 30, "90d" => 90 }[range]
    if days.nil? && range == "all"
      first = ErrorOccurrence.joins(:error_group).where(error_groups: { project_id: project.id }).minimum(:occurred_at)
      days = first ? [ (Date.current - first.to_date).to_i + 1, 1 ].max : 1
    end
    project_inbox_query(project).group_trends(groups, days: days || 7, dimensions: profile_filters)
  end

  def inbox_counts(project, assignee: "all", viewer: nil)
    project_inbox_query(project, viewer: viewer).counts(assignee: assignee)
  end

  def project_has_activity_events?(project)
    project_inbox_query(project).has_activity_events?
  end

  def inbox_impact_summaries(project, groups, profile_filters: {})
    return {} unless ProjectExperience.for(project).supports?(:mobile)

    range = profile_filters.to_h.stringify_keys["time_range"]
    duration = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days, "90d" => 90.days }[range]
    since = range == "all" ? nil : (duration || 30.days).ago
    occurrence_scope = project_inbox_query(project).occurrence_relation(profile_filters, group_ids: groups.map(&:id))
    ErrorGroupImpactSummary.for_groups(groups, since: since, occurrence_scope: occurrence_scope)
  end

  def inbox_android_mapping_resolutions(project, latest_events)
    return {} unless ProjectExperience.for(project).key == :android

    presenters = latest_events.values.compact.index_with { |event| ProjectEvents::AndroidEventPresenter.new(event) }
    mapping_keys = presenters.values.filter_map do |presenter|
      app = presenter.app_details
      next if app[:package_name].blank? || app[:version_code].blank?

      [ app[:package_name], app[:version_code].to_s ]
    end.uniq

    mappings = mapping_keys
      .reduce(project.android_mapping_files.none) do |relation, (package_name, version_code)|
        relation.or(project.android_mapping_files.where(package_name:, version_code:))
      end
      .to_a
      .index_by { |mapping| [ mapping.package_name, mapping.version_code.to_s ] }

    presenters.to_h do |event, presenter|
      app = presenter.app_details
      mapping = mappings[[ app[:package_name], app[:version_code].to_s ]]
      resolution = AndroidMappingResolution.call(project:, event:, presenter:, mapping_file: mapping)
      [ event.id, resolution ]
    end
  end

  def inbox_ios_symbol_coverages(project, latest_events)
    return {} unless ProjectExperience.for(project).key == :ios

    presenters = latest_events.values.compact.index_with { |event| ProjectEvents::IosEventPresenter.new(event) }
    build_keys = presenters.values.filter_map do |presenter|
      app = presenter.app_details
      next if app[:bundle_identifier].blank? || app[:version_code].blank?

      [ app[:bundle_identifier], app[:version_code].to_s ]
    end.uniq

    artifacts = build_keys
      .reduce(project.apple_symbol_artifacts.none) do |relation, (app_identifier, version_code)|
        relation.or(project.apple_symbol_artifacts.where(app_identifier:, version_code:))
      end
      .to_a
      .group_by { |artifact| [ artifact.app_identifier, artifact.version_code.to_s ] }

    presenters.to_h do |event, presenter|
      app = presenter.app_details
      coverage = AppleSymbolCoverage.call(
        project:,
        event:,
        presenter:,
        artifacts: artifacts.fetch([ app[:bundle_identifier], app[:version_code].to_s ], [])
      )
      [ event.id, coverage ]
    end
  end

  def normalize_inbox_assignee_filter(project, assignee, viewer: nil)
    project_inbox_query(project, viewer: viewer).normalize_assignee(assignee)
  end

  def normalize_inbox_profile_filters(project, source = params)
    allowed = ProjectExperience.for(project).filters.map { |definition| definition.key.to_s }
    values = source.respond_to?(:to_unsafe_h) ? source.to_unsafe_h : source.to_h
    values.stringify_keys.slice(*allowed).transform_values { |value| value.to_s.strip }.compact_blank
  end

  def normalize_inbox_sort(project, value)
    profile = ProjectExperience.for(project)
    value.to_s.presence_in(profile.sort_options.map(&:last)) || profile.default_sort
  end

  def inbox_profile_state_params(project, source = params)
    state = normalize_inbox_profile_filters(project, source)
    raw_sort = source.respond_to?(:[]) ? (source[:sort] || source["sort"]) : nil
    state["sort"] = normalize_inbox_sort(project, raw_sort) if raw_sort.present?
    state
  end

  def inbox_filter_options(project)
    project_inbox_query(project).filter_options
  end

  def project_inbox_query(project, viewer: nil)
    ProjectInboxQuery.new(project: project, viewer: viewer)
  end
end

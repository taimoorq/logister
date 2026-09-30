# frozen_string_literal: true

class ProjectPageContext
  attr_reader :project,
              :viewer,
              :integration_definition,
              :experience_definition,
              :navigation,
              :request_path,
              :settings_only

  def self.for(project:, viewer:, request_path:, app_admin: false, page_key: nil)
    new(project: project, viewer: viewer, request_path: request_path, app_admin: app_admin, page_key: page_key)
  end

  def initialize(project:, viewer:, request_path:, app_admin: false, page_key: nil)
    @project = project
    @viewer = viewer
    @request_path = request_path
    @integration_definition = project.integration_definition
    @experience_definition = ProjectExperience.definition_for(project.integration_kind)

    policy = ProjectPagePolicy.new(project: project, viewer: viewer, app_admin: app_admin)
    @settings_only = policy.settings_only?
    pages = policy.resolve(experience_definition.pages).sort_by(&:order)
    current_page_key = if page_key
      page_key.to_sym
    else
      pages.find do |page|
        page.route_key && ProjectPageRoutes.path_for(page.route_key, project) == request_path
      end&.key
    end
    if project.persisted?
      @capability_snapshot = ProjectCapabilitySnapshot.for(project)
      pages = ProjectNavigationProjection.new(project: project, capability_snapshot: @capability_snapshot)
                                         .resolve(pages, current_page_key: current_page_key)
                                         .sort_by(&:order)
    end
    current_page = pages.find { |page| page.key == current_page_key }
    @navigation = ResolvedNavigation.new(tabs: build_tabs(pages), current_page: current_page)
  end

  def page
    navigation.current_page
  end

  # The setup chip needs a project member who can open Setup.
  def setup_chip?
    viewer.present? && !settings_only && project.persisted? && !project.archived? && !project.purge_pending?
  end

  def capability_snapshot
    @capability_snapshot ||= ProjectCapabilitySnapshot.for(project)
  end

  def path_for(page_definition)
    raise ArgumentError, "Hidden project pages do not have navigation paths" unless page_definition.route_key

    ProjectPageRoutes.path_for(page_definition.route_key, project)
  end

  def active?(page_definition)
    page&.key == page_definition.key
  end

  private

  def build_tabs(pages)
    ProjectNavSection::ALL.filter_map do |section|
      section_pages = pages.select { |candidate| candidate.section_key == section.key }
      next unless section_pages.any? { |candidate| !candidate.hidden? }

      ResolvedNavigation::Tab.new(section: section, pages: section_pages.freeze)
    end
  end
end

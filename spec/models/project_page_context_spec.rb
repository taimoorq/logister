# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectPageContext do
  # Every project type shares the same sections in the same order. Optional
  # sections appear from observed state, never from the project's type.
  BASE_SECTIONS = %w[Overview Issues Performance Releases Explore].freeze

  def routes
    Rails.application.routes.url_helpers
  end

  def context_for(project, path: nil, **options)
    described_class.for(
      project: project,
      viewer: project.user,
      request_path: path || routes.project_path(project),
      **options
    )
  end

  def tab_labels(context)
    context.navigation.tabs.map(&:label)
  end

  def view_labels(context)
    context.navigation.current_tab.views.map(&:view_label)
  end

  it "gives every project type the same section order, with Settings last" do
    %i[ruby cfml javascript python dotnet cloudflare_pages android ios].each do |kind|
      project = create(:project, kind)

      expect(tab_labels(context_for(project))).to eq([ *BASE_SECTIONS, "Settings" ]), "#{kind} sections differ"
    end
  end

  it "pins Settings to the end of the tab bar" do
    context = context_for(create(:project, :ruby))

    expect(context.navigation.tabs.last.pinned?).to be(true)
    expect(context.navigation.tabs.count(&:pinned?)).to eq(1)
  end

  it "opens the section entry page for each type" do
    server = context_for(create(:project, :ruby))
    mobile = context_for(create(:project, :android))
    entry = ->(context, label) { context.navigation.tabs.find { |tab| tab.label == label }.entry_page.key }

    expect(entry.call(server, "Issues")).to eq(:inbox)
    expect(entry.call(server, "Releases")).to eq(:deployments)
    expect(entry.call(server, "Explore")).to eq(:activity)
    expect(entry.call(mobile, "Issues")).to eq(:inbox)
    expect(entry.call(mobile, "Releases")).to eq(:releases)
    expect(entry.call(mobile, "Explore")).to eq(:activity)
  end

  it "uses shared labels while keeping mobile evidence vocabulary in descriptions" do
    server = create(:project, :ruby)
    mobile = create(:project, :ios)

    server_page = context_for(server, path: routes.inbox_project_path(server)).page
    mobile_context = context_for(mobile, path: routes.inbox_project_path(mobile))

    expect(mobile_context.page.label).to eq(server_page.label)
    expect(mobile_context.page.label).to eq("Issues")
    expect(mobile_context.page.description).to include("Crashes")
    expect(mobile_context.experience_definition.family_key).to eq(:mobile_application)

    performance = context_for(mobile, path: routes.performance_project_path(mobile)).page
    expect(performance.label).to eq("Performance")
    expect(performance.header_label).to eq("Project app health")
  end

  it "keeps the current tab, and only that tab, marked active" do
    project = create(:project, :ruby)
    context = context_for(project, path: routes.performance_project_path(project))

    expect(context.page.key).to eq(:performance)
    expect(context.navigation.tabs.select { |tab| context.navigation.current?(tab) }.map(&:label)).to eq([ "Performance" ])
  end

  describe "section views" do
    it "shows Explore views for every type, and hides the Connected view until projects are linked" do
      %i[ruby android].each do |kind|
        project = create(:project, kind)
        context = context_for(project, path: routes.activity_project_path(project))

        expect(view_labels(context)).to eq(%w[Events Charts Archive]), "#{kind} explore views differ"
        expect(context.navigation.views.map(&:key)).to eq(%i[activity insights archives])
      end
    end

    it "adds the Connected view once correlations are enabled and the project is linked" do
      allow(ProjectCorrelationPolicy).to receive(:instance_enabled?).and_return(true)
      backend = create(:project, :ruby, cross_project_correlations_enabled: true)
      app = create(:project, :android, user: backend.user, cross_project_correlations_enabled: true)

      expect(view_labels(context_for(backend, path: routes.activity_project_path(backend)))).not_to include("Connected")

      ProjectLink.create!(source_project: app, target_project: backend, created_by: backend.user,
                          environment_pairs: [ { "source" => "production", "target" => "production" } ])

      context = context_for(backend, path: routes.activity_project_path(backend))
      expect(view_labels(context)).to eq(%w[Events Charts Archive Connected])
    end

    it "gives server projects one Releases view and mobile projects Releases and Artifacts" do
      server = create(:project, :ruby)
      android = create(:project, :android)

      server_context = context_for(server, path: routes.deployments_project_path(server))
      mobile_context = context_for(android, path: routes.releases_project_path(android))

      expect(server_context.navigation.views).to be_empty
      expect(view_labels(mobile_context)).to eq(%w[Releases Artifacts])
    end

    it "shows mobile Deploy records only after a deployment is recorded, but keeps the page reachable" do
      project = create(:project, :ios)

      expect(view_labels(context_for(project, path: routes.releases_project_path(project)))).to eq(%w[Releases Artifacts])
      direct = context_for(project, path: routes.deployments_project_path(project))
      expect(view_labels(direct)).to eq([ "Releases", "Artifacts", "Deploy records" ])
      expect(direct.page.key).to eq(:deployments)

      create(:project_deployment, project: project)
      recorded = context_for(project, path: routes.releases_project_path(project))
      expect(view_labels(recorded)).to eq([ "Releases", "Artifacts", "Deploy records" ])
    end

    it "has no sub-navigation for sections with a single view" do
      project = create(:project, :ruby)

      %i[inbox performance monitors].each do |page|
        path = routes.public_send("#{page}_project_path", project)
        expect(context_for(project, path: path).navigation.views).to be_empty
      end
    end
  end

  describe "Monitors" do
    it "appears for every type once a check-in monitor exists, and stays reachable by direct visit" do
      %i[ruby android].each do |kind|
        project = create(:project, kind)

        expect(tab_labels(context_for(project))).not_to include("Monitors")

        direct = context_for(project, path: routes.monitors_project_path(project))
        expect(tab_labels(direct)).to include("Monitors")
        expect(direct.page.key).to eq(:monitors)

        create(:check_in_monitor, project: project)
        expect(tab_labels(context_for(project))).to include("Monitors"), "#{kind} monitors should appear"
      end
    end
  end

  describe "pages without their own tab" do
    it "keeps the hidden setup route inside Settings" do
      project = create(:project, :ruby)
      context = context_for(project, path: routes.setup_project_path(project))

      expect(context.page.key).to eq(:setup)
      expect(context.page.header_label).to eq("Project setup")
      expect(context.navigation.current_tab.key).to eq(:settings)
    end

    it "gives connected projects and correlations a section instead of leaving no tab active" do
      project = create(:project, :ruby)

      links = context_for(project, path: routes.project_project_links_path(project))
      expect(links.page.key).to eq(:project_links)
      expect(links.navigation.current_tab.key).to eq(:settings)

      connections = context_for(project, path: routes.connections_project_path(project))
      expect(connections.page.key).to eq(:connections)
      expect(connections.navigation.current_tab.key).to eq(:explore)

      related = context_for(project, path: "/requests/dynamic-id", page_key: :correlations)
      expect(related.page.header_label).to eq("Connected impact")
      expect(related.navigation.current_tab.key).to eq(:explore)
    end

    it "uses explicit hidden event pages while keeping their section current" do
      project = create(:project, :ios)

      issue = context_for(project, path: "/events/dynamic-id", page_key: :error_event)
      expect(issue.page.header_label).to eq("Project issue")
      expect(issue.navigation.current_tab.key).to eq(:issues)

      event = context_for(project, path: "/events/dynamic-id", page_key: :activity_event)
      expect(event.navigation.current_tab.key).to eq(:explore)
    end
  end

  it "does not render dead project links for an app admin with settings-only access" do
    viewer = create(:user, application_admin: true)
    project = create(:project)
    context = described_class.for(
      project: project,
      viewer: viewer,
      request_path: routes.settings_project_path(project),
      app_admin: true
    )

    expect(context.navigation.tabs.map(&:key)).to eq([ :settings ])
    expect(context.page.key).to eq(:settings)
  end

  it "assigns every navigable route to a section for every experience" do
    ProjectExperienceDefinition.keys.each do |experience_key|
      pages = ProjectPageCatalog.fetch(experience_key)

      expect(pages.map(&:section_key) - ProjectNavSection::KEYS).to be_empty
      expect(pages.select { |page| page.route_key.nil? && !page.hidden? }).to be_empty
    end
  end

  it "validates every experience page catalog and keeps it query-free" do
    queries = capture_sql do
      ProjectExperienceDefinition.keys.each do |experience_key|
        expect(ProjectPageCatalog.validate!(experience_key)).to be(true)
        expect(ProjectPageCatalog.fetch(experience_key)).to be_frozen
        expect(ProjectPageCatalog.fetch(experience_key)).to all(be_frozen)
      end
    end

    expect(queries).to be_empty
  end

  it "rejects a catalog that leaves a section with no navigable page" do
    allow(ProjectPageCatalog).to receive(:fetch).and_return(
      ProjectPageCatalog.fetch(:server).reject { |page| page.section_key == :monitors }
    )

    expect { ProjectPageCatalog.validate!(:server) }.to raise_error(ArgumentError, /without a navigable page/)
  end
end

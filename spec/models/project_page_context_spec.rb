# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectPageContext do
  EXPECTED_SERVER_NAVIGATION = %w[
    Overview Inbox Events Insights Performance Monitors Deployments Archive\ search Settings
  ].freeze
  EXPECTED_MOBILE_NAVIGATION = %w[
    Overview Stability Activity Insights App\ health Releases Check-ins Deployments Archive\ search Settings
  ].freeze

  def navigation_labels(context)
    [ *context.navigation.primary_pages, *context.navigation.secondary_pages ].map(&:label)
  end

  it "composes the unchanged server navigation from static page definitions" do
    project = build(:project, :ruby, uuid: SecureRandom.uuid)
    context = described_class.for(
      project: project,
      viewer: project.user,
      request_path: Rails.application.routes.url_helpers.performance_project_path(project)
    )

    expect(navigation_labels(context)).to eq(EXPECTED_SERVER_NAVIGATION)
    expect(context.page.key).to eq(:performance)
    expect(context.page.header_label).to eq("Project performance")
    expect(context.navigation.primary_pages.count { |page| context.active?(page) }).to eq(1)
  end

  it "applies the shared mobile family vocabulary to Android and iOS" do
    %i[android ios].each do |kind|
      project = build(:project, kind, uuid: SecureRandom.uuid)
      context = described_class.for(
        project: project,
        viewer: project.user,
        request_path: Rails.application.routes.url_helpers.inbox_project_path(project)
      )

      expect(navigation_labels(context)).to eq(EXPECTED_MOBILE_NAVIGATION)
      expect(context.page.header_label).to eq("Project stability")
      expect(context.navigation.primary_pages.find { |page| page.key == :performance }.header_label).to eq("Project app health")
      expect(context.experience_definition.family_key).to eq(:mobile_application)
    end
  end

  it "keeps a hidden setup route distinct while marking Settings as its active parent" do
    project = build(:project, :ruby, uuid: SecureRandom.uuid)
    context = described_class.for(
      project: project,
      viewer: project.user,
      request_path: Rails.application.routes.url_helpers.setup_project_path(project)
    )
    settings_page = context.navigation.secondary_pages.find { |page| page.key == :settings }

    expect(context.page.key).to eq(:setup)
    expect(context.page.header_label).to eq("Project setup")
    expect(context.active?(settings_page)).to be(true)
    expect(context.navigation.secondary_active?).to be(true)
  end

  it "uses an explicit hidden event page while keeping its navigation parent active" do
    project = build(:project, :ios, uuid: SecureRandom.uuid)
    context = described_class.for(
      project: project,
      viewer: project.user,
      request_path: "/events/dynamic-id",
      page_key: :error_event
    )
    stability_page = context.navigation.primary_pages.find { |page| page.key == :inbox }

    expect(context.page.key).to eq(:error_event)
    expect(context.page.header_label).to eq("Project issue")
    expect(context.active?(stability_page)).to be(true)
  end

  it "does not render dead project links for an app admin with settings-only access" do
    viewer = create(:user, application_admin: true)
    project = create(:project)
    context = described_class.for(
      project: project,
      viewer: viewer,
      request_path: Rails.application.routes.url_helpers.settings_project_path(project),
      app_admin: true
    )

    expect(context.navigation.primary_pages).to be_empty
    expect(context.navigation.secondary_pages.map(&:key)).to eq([ :settings ])
    expect(context.page.key).to eq(:settings)
  end

  it "validates every experience page catalog and keeps it query-free" do
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      queries << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      ProjectExperienceDefinition.keys.each do |experience_key|
        expect(ProjectPageCatalog.validate!(experience_key)).to be(true)
        expect(ProjectPageCatalog.fetch(experience_key)).to be_frozen
        expect(ProjectPageCatalog.fetch(experience_key)).to all(be_frozen)
      end
    end

    expect(queries).to be_empty
  end
end

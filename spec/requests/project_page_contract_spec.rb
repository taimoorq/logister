# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Project page contract", type: :request do
  PAGE_PATHS = {
    overview: ->(project) { project_path(project) },
    inbox: ->(project) { inbox_project_path(project) },
    activity: ->(project) { activity_project_path(project) },
    insights: ->(project) { insights_project_path(project) },
    performance: ->(project) { performance_project_path(project) },
    monitors: ->(project) { monitors_project_path(project) },
    deployments: ->(project) { deployments_project_path(project) },
    archives: ->(project) { archives_project_path(project) },
    setup: ->(project) { setup_project_path(project) },
    settings: ->(project) { settings_project_path(project) },
    edit: ->(project) { edit_project_path(project) }
  }.freeze

  before { sign_in users(:one) }

  it "renders one coherent project shell for every registered type and declared route" do
    Project.integration_kinds.each_key do |kind|
      project = create(:project, user: users(:one), integration_kind: kind)
      expected_experience = ProjectIntegrationDefinition.fetch(kind).default_experience_key.to_s

      PAGE_PATHS.each do |page_key, path_builder|
        get instance_exec(project, &path_builder)

        aggregate_failures("#{kind} #{page_key}") do
          expect(response).to have_http_status(:success)

          document = Nokogiri::HTML.parse(response.body)
          header = document.at_css(".project-command-panel")
          navigation = document.at_css("nav[aria-label='Project sections']")

          expect(header).to be_present
          expect(header["data-project-kind"]).to eq(kind)
          expect(header["data-project-experience"]).to eq(expected_experience)
          expect(header["data-project-page"]).to eq(page_key.to_s)
          expect(navigation).to be_present
          expect(navigation.css("a[aria-current='page']").size).to eq(1)
        end
      end
    end
  end

  it "exposes the Releases destination only for mobile project definitions" do
    %i[android ios].each do |kind|
      project = create(:project, user: users(:one), integration_kind: kind)

      get releases_project_path(project)

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML.parse(response.body)
      expect(document.at_css(".project-command-panel")&.[]("data-project-page")).to eq("releases")
      expect(document.css("a[aria-current='page']").map(&:text).join).to include("Releases")
    end

    project = create(:project, user: users(:one), integration_kind: :ruby)
    get releases_project_path(project)
    expect(response).to have_http_status(:not_found)
  end

  it "exposes the paginated Artifacts destination only for mobile project definitions" do
    %i[android ios].each do |kind|
      project = create(:project, user: users(:one), integration_kind: kind)

      get artifacts_project_path(project)

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML.parse(response.body)
      expect(document.at_css(".project-command-panel")&.[]("data-project-page")).to eq("artifacts")
      expect(document.css("a[aria-current='page']").map(&:text).join).to include("Artifacts")
    end

    get artifacts_project_path(create(:project, user: users(:one), integration_kind: :ruby))
    expect(response).to have_http_status(:not_found)
  end

  it "uses the mobile stability overview instead of server request and database cards" do
    project = create(:project, user: users(:one), integration_kind: :ios)

    get project_path(project)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Current stability", "Observed builds", "Denominators are explicit")
    expect(response.body).not_to include("Request timing", "DB queries")
  end

  it "uses a mobile app-health view without loading server request or database frames" do
    project = create(:project, user: users(:one), integration_kind: :android)

    get performance_project_path(project)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Responsiveness and resource evidence", "App-supplied telemetry")
    expect(response.body).not_to include("Request load breakdown", "Database load", "performance_request_breakdown")

    get performance_request_breakdown_project_path(project)
    expect(response).to redirect_to(performance_project_path(project))
  end
end

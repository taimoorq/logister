# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Project experience contract", type: :request do
  before { sign_in users(:one) }

  it "renders the shared inbox shell for every supported project kind" do
    Project.integration_kinds.each_key do |kind|
      project = create(:project, user: users(:one), integration_kind: kind)

      get inbox_project_path(project)

      expect(response).to have_http_status(:success), "expected #{kind} inbox to render"
      expect(response.body).to include("turbo-frame id=\"project_inbox\"", "data-project-integration=\"#{kind}\"")

      document = Nokogiri::HTML.parse(response.body)
      header = document.at_css(".project-command-panel")
      navigation = document.at_css("nav[aria-label='Project sections']")
      active_links = navigation.css("a[aria-current='page']")
      expected_experience = ProjectIntegrationDefinition.fetch(kind).default_experience_key.to_s

      expect(header["data-project-kind"]).to eq(kind)
      expect(header["data-project-experience"]).to eq(expected_experience)
      expect(header["data-project-experience-version"]).to eq(ProjectExperience.definition_for(kind).version.to_s)
      expect(header["data-project-page"]).to eq("inbox")
      expect(active_links.size).to eq(1)
      expect(active_links.first.text.strip).to eq(%w[android ios].include?(kind) ? "Stability" : "Inbox")
    end
  end

  it "never returns a mismatched inbox or detail fragment to an unexpected Turbo Frame" do
    project = create(:project, user: users(:one), integration_kind: "ruby")
    api_key = create(:api_key, project: project, user: users(:one))
    event = create(:ingest_event, project: project, api_key: api_key, event_type: :error, level: "error")
    ErrorGroupingService.call(event)

    get project_events_path(project), headers: { "Turbo-Frame" => "wrong_inbox" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to be_blank

    get project_event_path(project, event), headers: { "Turbo-Frame" => "wrong_detail" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to be_blank
  end
end

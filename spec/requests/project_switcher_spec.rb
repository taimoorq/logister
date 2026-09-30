# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Switching projects from the top menu", type: :request do
  let(:user) { users(:one) }
  let!(:first_project) { create(:project, :python, user: user, name: "First Switch App") }
  let!(:second_project) { create(:project, :android, user: user, name: "Second Switch App") }

  def menu_links
    Nokogiri::HTML.parse(response.body).css(".nav-project-menu .nav-project-item").to_h do |link|
      [ link.at_css(".nav-project-item-title").text.strip, link["href"] ]
    end
  end

  before { sign_in user }

  it "keeps the section you are in when you pick another project" do
    get inbox_project_path(first_project)

    expect(menu_links["Second Switch App"]).to eq(inbox_project_path(second_project))
    expect(menu_links["First Switch App"]).to eq(inbox_project_path(first_project))
  end

  it "keeps Explore on its first view, and Settings on Settings" do
    get activity_project_path(first_project)
    expect(response).to have_http_status(:success)
    expect(menu_links["Second Switch App"]).to eq(activity_project_path(second_project))

    get settings_project_path(first_project)
    expect(menu_links["Second Switch App"]).to eq(settings_project_path(second_project))
  end

  it "follows the section into a hidden page such as an issue's detail" do
    api_key = create(:api_key, project: first_project, user: user)
    error = create(:ingest_event, project: first_project, api_key: api_key, event_type: "error", level: "error", message: "Switch me")

    get project_event_path(first_project, error)

    expect(response).to have_http_status(:success)
    expect(menu_links["Second Switch App"]).to eq(inbox_project_path(second_project))
  end

  it "opens the project overview from pages that are not a project's" do
    get dashboard_path

    expect(menu_links["Second Switch App"]).to eq(project_path(second_project))
  end

  it "calls the top link Dashboard" do
    get dashboard_path

    labels = Nokogiri::HTML.parse(response.body).css("nav.nav-shell a").map { |node| node.text.squish }
    expect(labels).to include("Dashboard")
    expect(labels).not_to include("Overview")
  end
end

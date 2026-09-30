# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Explore keeps one scope across its views", type: :request do
  let(:owner) { users(:one) }
  let(:project) { create(:project, :ruby, user: owner) }

  def sub_links
    Nokogiri::HTML.parse(response.body).css("nav[aria-label='Explore views'] a").to_h { |link| [ link.text.squish.split(". ").first.strip, link["href"] ] }
  end

  def query_of(href)
    Rack::Utils.parse_nested_query(URI(href).query)
  end

  before { sign_in owner }

  it "carries the time window, environment and release from Events to Charts" do
    get activity_project_path(project, period: "24h", environment: "production", release: "1.4.2")

    charts = query_of(sub_links.fetch("Charts"))
    expect(charts).to include("window" => "24h", "environment" => "production", "release" => "1.4.2")
  end

  it "carries the scope from Charts back to Events under Events' own names" do
    get insights_project_path(project, window: "6h", environment: "staging")

    events = query_of(sub_links.fetch("Events"))
    expect(events).to include("environment" => "staging")
    expect(events).not_to have_key("window")
  end

  it "names a filter that cannot carry to a view, rather than silently dropping it" do
    get activity_project_path(project, period: "90d", environment: "production")

    charts_link = Nokogiri::HTML.parse(response.body).css("nav[aria-label='Explore views'] a").find { |link| link.text.include?("Charts") }
    expect(charts_link.at_css(".sr-only").text).to include("window does not carry over to this view")
    expect(query_of(charts_link["href"])).to include("environment" => "production")
    expect(query_of(charts_link["href"])).not_to have_key("window")
  end

  it "uses plain links when there is no scope to carry" do
    get activity_project_path(project)

    expect(sub_links.fetch("Charts")).to eq(insights_project_path(project))
    expect(sub_links.fetch("Archive")).to eq(archives_project_path(project))
  end

  it "does not add scope to the Releases views" do
    get deployments_project_path(create(:project, :ios, user: owner), environment: "production")

    expect(response.body).not_to include("carry over")
  end

  it "carries environment and release into Connected once projects are linked" do
    allow(ProjectCorrelationPolicy).to receive(:instance_enabled?).and_return(true)
    backend = create(:project, :ruby, user: owner, cross_project_correlations_enabled: true)
    app = create(:project, :android, user: owner, cross_project_correlations_enabled: true)
    ProjectLink.create!(source_project: app, target_project: backend, created_by: owner,
                        environment_pairs: [ { "source" => "production", "target" => "production" } ])

    get activity_project_path(backend, environment: "production", release: "9.9")

    expect(query_of(sub_links.fetch("Connected"))).to include("environment" => "production", "release" => "9.9")
  end
end

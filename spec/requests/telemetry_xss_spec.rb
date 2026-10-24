# frozen_string_literal: true

require "rails_helper"

# Telemetry is written by anyone holding an ingest key, so every string it
# carries must render as text, and only vetted URLs may become links.
RSpec.describe "Telemetry XSS regressions", type: :request do
  let(:script_payload) { "<script>alert(\"logister-xss\")</script>" }
  let(:img_payload) { "<img src=x onerror=alert(\"logister-xss\")>" }
  let(:javascript_url) { "javascript:alert(\"logister-xss\")" }
  let(:phishing_url) { "https://phish.example/login" }

  let(:user) { users(:one) }
  let(:project) { create(:project, user: user, name: "XSS App") }
  let(:api_key) { create(:api_key, project: project, user: user) }
  let(:repository) { create(:project_source_repository, project: project, full_name: "acme/storefront") }

  before { sign_in user }

  def unsafe_deployment_metadata
    {
      "pull_request_number" => "42",
      "pull_request_url" => javascript_url,
      "release_tag" => script_payload,
      "release_url" => phishing_url,
      "compare_url" => javascript_url,
      "workflow_run_url" => javascript_url,
      "deployment_url" => phishing_url
    }
  end

  def create_unsafe_deployment(**attributes)
    # update_columns simulates rows stored before write-time URL validation.
    create(:project_deployment, project: project, project_source_repository: repository,
           repository_full_name: "acme/storefront", **attributes).tap do |deployment|
      deployment.update_columns(metadata: unsafe_deployment_metadata, branch: script_payload)
    end
  end

  def expect_no_executable_payload(html)
    document = Nokogiri::HTML(html)

    scripts = document.css("script").map(&:text).join("\n")
    expect(scripts).not_to include("logister-xss")
    expect(document.css("img[onerror]")).to be_empty
    handler_attributes = document.xpath("//@*[starts-with(name(), 'on')]").map(&:value)
    expect(handler_attributes.join("\n")).not_to include("logister-xss")

    hrefs = document.css("[href]").map { |node| node["href"].to_s.strip.downcase }
    expect(hrefs).to all(satisfy { |href| !href.start_with?("javascript:", "data:", "vbscript:") })
    expect(hrefs.join("\n")).not_to include("phish.example")
    expect(document.css("[src]").map { |node| node["src"].to_s.downcase }).to all(satisfy { |src| !src.start_with?("javascript:") })
  end

  it "renders event detail telemetry as text" do
    event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      message: "#{script_payload} #{img_payload}",
      context: {
        "environment" => script_payload,
        "release" => script_payload,
        "exception" => {
          "class" => script_payload,
          "message" => img_payload,
          "backtrace" => [ "#{script_payload}:12:in 'call'" ]
        },
        "request" => { "method" => "GET", "url" => javascript_url, "path" => script_payload },
        "user_id" => img_payload,
        "tags" => { script_payload => img_payload }
      }
    )
    ErrorGroupingService.call(event)

    get project_event_path(project, event), headers: { "Turbo-Frame" => "error_detail" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include(ERB::Util.html_escape(script_payload))
    expect_no_executable_payload(response.body)
  end

  it "never links stored unsafe deployment URLs on the deployments page" do
    create_unsafe_deployment(release: "2026.06.17", commit_sha: "abc1234", deployed_at: 1.day.ago)
    create_unsafe_deployment(release: script_payload, commit_sha: "def5678", deployed_at: 1.hour.ago)

    get deployments_project_path(project)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("https://github.com/acme/storefront/pull/42")
    expect_no_executable_payload(response.body)
  end

  it "never links stored unsafe deployment URLs in the event deployment context panel" do
    create_unsafe_deployment(release: "2026.06.17", commit_sha: "abc1234", deployed_at: 2.hours.ago)
    create_unsafe_deployment(release: "2026.06.18", commit_sha: "def5678", deployed_at: 30.minutes.ago)
    event = create(:ingest_event, project: project, api_key: api_key, message: "Boom",
                   context: { "release" => "2026.06.18", "environment" => "production", "repository" => "acme/storefront" })
    ErrorGroupingService.call(event)
    project.error_groups.update_all(first_seen_at: 10.minutes.ago, stage: "production")

    get project_event_path(project, event), headers: { "Turbo-Frame" => "error_detail" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Deployment context")
    expect(response.body).to include("https://github.com/acme/storefront/pull/42")
    expect_no_executable_payload(response.body)
  end

  it "returns insights telemetry as escaped JSON data" do
    travel_to Time.zone.local(2026, 5, 21, 12, 0, 0) do
      context = { "environment" => "production", "release" => script_payload, script_payload => javascript_url }
      create(:ingest_event, project: project, api_key: api_key, message: script_payload, context: context, occurred_at: 10.minutes.ago)
      create(:ingest_event, :log, project: project, api_key: api_key, message: img_payload, context: context, occurred_at: 5.minutes.ago)

      get insights_data_project_path(project), params: { window: "1h" }

      expect(response).to have_http_status(:success)
      # Rails 8.1 does not HTML-escape JSON bodies, so the guard is that the
      # payload is served as JSON the browser will not sniff into HTML, and
      # that Stimulus receives the strings as data to escape on insertion.
      expect(response.media_type).to eq("application/json")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")

      json = JSON.parse(response.body)
      recent_messages = json.fetch("recent_events").map { |recent| recent["message"] }
      expect(recent_messages).to include(script_payload, img_payload)
      expect(json.fetch("releases").map { |release| release["name"] }).to include(script_payload)
    end
  end
end

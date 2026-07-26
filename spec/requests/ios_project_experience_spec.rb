# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "iOS project experience", type: :request do
  let(:payload) { JSON.parse(Rails.root.join("spec/fixtures/files/ios_error_payload.json").read) }
  let(:project) { create(:project, :ios, user: users(:one), name: "Acme iOS") }
  let(:api_key) { create(:api_key, project: project, user: users(:one)) }
  let!(:event) do
    create(
      :ingest_event,
      project: project,
      api_key: api_key,
      event_type: :error,
      level: payload.fetch("level"),
      message: payload.fetch("message"),
      context: payload.fetch("context")
    ).tap { |created_event| ErrorGroupingService.call(created_event) }
  end

  before { sign_in users(:one) }

  it "renders an iOS-specific experience through the shared profile contract" do
    get inbox_project_path(project, group_uuid: event.error_group.uuid)

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML.parse(response.body)
    expect(document.at_css("[data-project-experience='ios']")).to be_present
    expect(document.css(".detail-tab").map { |tab| tab.text.strip }).to eq([
      "Stack trace", "Trail", "Occurrences (1)", "App & device", "Raw"
    ])
    expect(document.text).to include("CheckoutError", "CheckoutViewModel.submit(_:)", "dSYM coverage is not configured")
    expect(document.text).to include("iPhone17,1", "iOS 19.0")
  end
end

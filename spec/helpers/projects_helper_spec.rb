# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectsHelper, type: :helper do
  describe "#project_integration_docs_path" do
    it "points Manual / HTTP API projects to the HTTP API docs" do
      project = Project.new(integration_kind: "http_api")

      expect(helper.project_integration_docs_path(project)).to eq("https://docs.logister.org/http-api/")
      expect(helper.project_integration_docs_label(project)).to eq("HTTP API docs")
    end

    it "points planned Cloudflare projects to the HTTP API docs until dedicated docs ship" do
      project = Project.new(integration_kind: "cloudflare_pages")

      expect(helper.project_integration_docs_path(project)).to eq("https://docs.logister.org/http-api/")
      expect(helper.project_integration_docs_label(project)).to eq("HTTP API docs")
    end

    it "points Android projects to the public Android SDK repo" do
      project = Project.new(integration_kind: "android")

      expect(helper.project_integration_docs_path(project)).to eq("https://github.com/taimoorq/logister-android")
      expect(helper.project_integration_docs_label(project)).to eq("Android SDK docs")
    end

    it "points iOS projects to the public iOS SDK repo" do
      project = Project.new(integration_kind: "ios")

      expect(helper.project_integration_docs_path(project)).to eq("https://github.com/taimoorq/logister-ios")
      expect(helper.project_integration_docs_label(project)).to eq("iOS SDK docs")
    end
  end
end

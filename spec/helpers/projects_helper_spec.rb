# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectsHelper, type: :helper do
  describe "#project_integration_docs_path" do
    it "points Manual / HTTP API projects to the HTTP API docs" do
      project = Project.new(integration_kind: "http_api")

      expect(helper.project_integration_docs_path(project)).to eq("https://docs.logister.org/http-api/")
      expect(helper.project_integration_docs_label(project)).to eq("HTTP API docs")
    end

    it "points planned Cloudflare and mobile projects to the HTTP API docs until dedicated docs ship" do
      %w[cloudflare_pages android ios].each do |integration_kind|
        project = Project.new(integration_kind: integration_kind)

        expect(helper.project_integration_docs_path(project)).to eq("https://docs.logister.org/http-api/")
        expect(helper.project_integration_docs_label(project)).to eq("HTTP API docs")
      end
    end
  end
end

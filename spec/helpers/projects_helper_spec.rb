# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectsHelper, type: :helper do
  describe "#project_integration_picker_choices" do
    it "renders every registered integration from the canonical definition order" do
      choices = helper.project_integration_picker_choices

      expect(choices.map { |choice| choice.fetch(:value) }).to eq(
        %w[http_api cloudflare_pages android ios ruby dotnet javascript python cfml]
      )
      expect(choices).to all(include(:label, :badge, :description, :value))
    end
  end

  describe "#project_integration_docs_path" do
    it "points Manual / HTTP API projects to the HTTP API docs" do
      project = Project.new(integration_kind: "http_api")

      expect(helper.project_integration_docs_path(project)).to eq("https://logister.org/docs/http-api/")
      expect(helper.project_integration_docs_label(project)).to eq("HTTP API docs")
    end

    it "points Cloudflare Pages projects to the Cloudflare Pages docs" do
      project = Project.new(integration_kind: "cloudflare_pages")

      expect(helper.project_integration_docs_path(project)).to eq("https://logister.org/docs/integrations/cloudflare-pages/")
      expect(helper.project_integration_docs_label(project)).to eq("Cloudflare Pages docs")
    end

    it "points Android projects to the Android integration docs" do
      project = Project.new(integration_kind: "android")

      expect(helper.project_integration_docs_path(project)).to eq("https://logister.org/docs/integrations/android/")
      expect(helper.project_integration_docs_label(project)).to eq("Android SDK docs")
    end

    it "points iOS projects to the iOS integration docs" do
      project = Project.new(integration_kind: "ios")

      expect(helper.project_integration_docs_path(project)).to eq("https://logister.org/docs/integrations/ios/")
      expect(helper.project_integration_docs_label(project)).to eq("iOS SDK docs")
    end

    it "resolves every registered documentation key without type branches" do
      ProjectIntegrationDefinition.all.each do |definition|
        project = Project.new(integration_kind: definition.key)

        expect(helper.project_integration_docs_path(project)).to eq(helper.docs_site_url(definition.documentation_key))
        expect(helper.project_integration_docs_label(project)).to eq(definition.documentation_label)
      end
    end
  end
end

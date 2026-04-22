# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocsHelper, type: :helper do
  describe "#docs_section_items" do
    it "returns the getting started sections for the getting started page" do
      allow(helper).to receive(:request).and_return(double(path: docs_getting_started_path))

      expect(helper.docs_section_items).to include(
        [ "Getting started", "#getting-started" ],
        [ "Verify setup", "#verify-setup" ]
      )
    end

    it "returns the overview sections for the docs index page" do
      allow(helper).to receive(:request).and_return(double(path: docs_path))

      expect(helper.docs_section_items).to include(
        [ "Overview", "#overview" ],
        [ "Getting started next", "#getting-started-next" ]
      )
    end
  end

  describe "#docs_code_block" do
    it "renders a copy-enabled highlighted code block" do
      rendered = helper.docs_code_block("bundle install", language: "language-bash", shell: true)

      expect(rendered).to include("docs-code-block")
      expect(rendered).to include('data-controller="copy"')
      expect(rendered).to include('data-copy-target="source"')
      expect(rendered).to include("docs-code-language")
      expect(rendered).to include(">shell<")
      expect(rendered).to include("Copy")
      expect(rendered).to include("bundle")
      expect(rendered).to include("install")
    end
  end

  describe "#docs_output_block" do
    it "renders a labeled output block" do
      rendered = helper.docs_output_block("Project created", label: "Setup checklist")

      expect(rendered).to include("docs-output-block")
      expect(rendered).to include("docs-output-header")
      expect(rendered).to include("Setup checklist")
      expect(rendered).to include("Project created")
    end
  end

  describe "#docs_rouge_theme_css" do
    it "scopes Rouge styles to docs code blocks" do
      expect(helper.docs_rouge_theme_css).to include(".docs-code-content")
      expect(helper.docs_rouge_theme_css).to include("background-color")
    end
  end
end

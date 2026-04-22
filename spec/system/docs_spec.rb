# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Docs", type: :system do
  it "renders the public docs layout with sidebar navigation and code blocks" do
    visit docs_cfml_integration_path

    expect(page).to have_content("Integrate a Lucee or ColdFusion site with Logister.")
    expect(page).to have_css(".docs-sidebar")
    expect(page).to have_link("CFML integration", href: docs_cfml_integration_path)
    expect(page).to have_css(".docs-code-block", minimum: 1)
    expect(page).to have_button("Copy", minimum: 1)
  end
end

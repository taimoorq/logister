# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Dashboard", type: :request do
  describe "GET /dashboard" do
    it "requires authentication" do
      get dashboard_path
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in" do
      before { sign_in users(:one) }

      it "returns success" do
        get dashboard_path
        expect(response).to have_http_status(:success)
      end

      it "shows overview content and project count" do
        get dashboard_path
        expect(response.body).to include(projects(:one).name)
      end

      it "renders project cards with inbox headers and clickable counts" do
        project = projects(:one)

        get dashboard_path

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        card = document.css(".project-card").find { |node| node.text.include?(project.name) }

        expect(document.at_css(".projects-page")).to be_present
        expect(document.at_css(".projects-search input[aria-label='Search projects']")).to be_present
        expect(document.at_css("a.projects-new-button")["href"]).to eq(new_project_path)
        expect(card).to be_present
        expect(card.at_css(".project-card-header")["href"]).to eq(project_path(project))
        expect(card.at_css(".project-type-icon-ruby use")["href"]).to match(%r{streamline-freehand(?:-[a-f0-9]+)?\.svg#streamline-project-ruby\z})
        expect(card.at_css(".project-card-health")).to be_nil
        expect(card.text).not_to include("Session stability", "User stability", "Performance score")
        expect(card.at_css("a[href='#{project_path(project, filter: 'unresolved')}']")).to be_present
        expect(card.at_css("a[href='#{project_path(project, filter: 'all')}']")).to be_present
        expect(card.at_css("a[href='#{activity_project_path(project)}']")).to be_present
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Docs", type: :request do
  describe "GET /docs" do
    it "returns success and overview content" do
      get docs_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Public setup guides for Logister and its integrations.")
      expect(response.body).to include("Ruby integration")
      expect(response.body).to include("CFML integration")
    end
  end

  describe "GET /docs/integrations/ruby" do
    it "returns success and Ruby integration content" do
      get docs_ruby_integration_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Integrate a Ruby or Rails app with Logister.")
      expect(response.body).to include("logister-ruby")
      expect(response.body).to include("Ruby gem")
    end
  end

  describe "GET /docs/integrations/cfml" do
    it "returns success and CFML integration content" do
      get docs_cfml_integration_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Integrate a Lucee or ColdFusion site with Logister.")
      expect(response.body).to include("Application.cfc.onError()")
      expect(response.body).to include("CFML")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project experience contract", type: :request do
  before { sign_in users(:one) }

  it "renders the shared inbox shell for every supported project kind" do
    Project.integration_kinds.each_key do |kind|
      project = create(:project, user: users(:one), integration_kind: kind)

      get inbox_project_path(project)

      expect(response).to have_http_status(:success), "expected #{kind} inbox to render"
      expect(response.body).to include("turbo-frame id=\"project_inbox\"", "data-project-integration=\"#{kind}\"")
    end
  end
end

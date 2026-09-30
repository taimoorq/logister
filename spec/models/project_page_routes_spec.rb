# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectPageRoutes do
  let(:routes) { Rails.application.routes.url_helpers }
  let(:project) { create(:project, :python) }

  describe ".section_path" do
    it "opens a section on its first view" do
      expect(described_class.section_path(project, :issues)).to eq(routes.inbox_project_path(project))
      expect(described_class.section_path(project, :explore)).to eq(routes.activity_project_path(project))
      expect(described_class.section_path(project, :performance)).to eq(routes.performance_project_path(project))
    end

    it "accepts the section as a string, as the header publishes it" do
      expect(described_class.section_path(project, "releases")).to eq(routes.deployments_project_path(project))
    end

    it "follows the project's own experience" do
      android = create(:project, :android)

      expect(described_class.section_path(android, :releases)).to eq(routes.releases_project_path(android))
    end

    it "opens the overview for a section the project does not have" do
      expect(described_class.section_path(project, :nonsense)).to eq(routes.project_path(project))
    end

    it "costs no queries once the project is loaded" do
      project

      expect(capture_sql { described_class.section_path(project, :issues) }).to be_empty
    end
  end
end

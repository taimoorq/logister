# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectGithubInstallation, type: :model do
  describe "associations" do
    it "belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end

    it "belongs to github installation" do
      expect(described_class.reflect_on_association(:github_installation).macro).to eq(:belongs_to)
    end

    it "belongs to linked_by as an optional user" do
      association = described_class.reflect_on_association(:linked_by)

      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:class_name]).to eq("User")
      expect(association.options[:optional]).to be true
    end
  end

  it "requires one link per project and installation" do
    existing = create(:project_github_installation)
    duplicate = build(
      :project_github_installation,
      project: existing.project,
      github_installation: existing.github_installation
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:github_installation_id]).to be_present
  end

  it "uses uuid for routes" do
    link = create(:project_github_installation)

    expect(link.to_param).to eq(link.uuid)
  end
end

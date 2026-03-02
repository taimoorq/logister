# frozen_string_literal: true

require "rails_helper"

RSpec.describe Project, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:api_keys).dependent(:destroy) }
    it { is_expected.to have_many(:ingest_events).dependent(:destroy) }
    it { is_expected.to have_many(:error_groups).dependent(:destroy) }
    it { is_expected.to have_many(:project_memberships).dependent(:destroy) }
    it { is_expected.to have_many(:members).through(:project_memberships).source(:user) }
  end

  describe "validations" do
    it "validates presence of name, slug, uuid" do
      project = Project.new(user: users(:one))
      expect(project).not_to be_valid
      expect(project.errors[:name]).to be_present
    end

    it "parameterizes slug from name" do
      project = Project.new(user: users(:one), name: "My Cool App")
      project.valid?
      expect(project.slug).to eq("my-cool-app")
    end
  end

  describe ".accessible_to" do
    it "includes projects owned by the user" do
      user = users(:one)
      expect(Project.accessible_to(user)).to include(projects(:one))
    end

    it "includes projects shared with the user" do
      member = users(:two)
      expect(Project.accessible_to(member)).to include(projects(:one))
    end

    it "excludes projects the user has no access to" do
      user = users(:one)
      expect(Project.accessible_to(user)).not_to include(projects(:two))
    end
  end

  describe "#owned_by?" do
    it "returns true for the owner" do
      expect(projects(:one).owned_by?(users(:one))).to be true
    end

    it "returns false for a member" do
      expect(projects(:one).owned_by?(users(:two))).to be false
    end
  end

  describe "#to_param" do
    it "returns uuid" do
      expect(projects(:one).to_param).to eq(projects(:one).uuid)
    end
  end
end

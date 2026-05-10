# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectMembership, type: :model do
  describe "associations" do
    it "belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end

    it "belongs to user" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
    end
  end

  describe "validations" do
    it "validates uniqueness of user_id scoped to project_id" do
      existing = project_memberships(:one)
      dup = ProjectMembership.new(project: existing.project, user: existing.user)
      expect(dup).not_to be_valid
      expect(dup.errors[:user_id]).to be_present
    end
  end

  describe "enum role" do
    it "defaults to viewer" do
      membership = project_memberships(:one)
      expect(membership).to be_viewer
    end
  end

  describe "#to_param" do
    it "returns uuid" do
      expect(project_memberships(:one).to_param).to eq(project_memberships(:one).uuid)
    end
  end

  describe "assignment cleanup" do
    it "clears error group assignments when access is removed" do
      project = create(:project, user: users(:one))
      member = create(:user)
      membership = create(:project_membership, project: project, user: member)
      group = create(:error_group, project: project, assignee: member, assigned_by: users(:one), assigned_at: Time.current)

      membership.destroy!

      expect(group.reload.assignee).to be_nil
      expect(group.assigned_by).to be_nil
      expect(group.assigned_at).to be_nil
    end

    it "clears assignment audit metadata when the assigner loses access" do
      project = create(:project, user: users(:one))
      member = create(:user)
      assignee = create(:user)
      membership = create(:project_membership, project: project, user: member)
      create(:project_membership, project: project, user: assignee)
      group = create(:error_group, project: project, assignee: assignee, assigned_by: member, assigned_at: Time.current)

      membership.destroy!

      expect(group.reload.assignee).to eq(assignee)
      expect(group.assigned_by).to be_nil
      expect(group).to be_valid
    end
  end
end

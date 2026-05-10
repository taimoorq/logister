# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectAssignmentSummary, type: :model do
  describe "#open_count_for" do
    it "summarizes unresolved assigned and unassigned error groups for a project" do
      project = create(:project)
      member = create(:user)
      create(:project_membership, project: project, user: member)

      create(:error_group, project: project, assignee: project.user, assigned_by: project.user)
      create(:error_group, project: project, assignee: member, assigned_by: project.user)
      create(:error_group, :resolved, project: project, assignee: member, assigned_by: project.user)
      create(:error_group, project: project)
      create(:error_group)

      summary = described_class.new(project)

      expect(summary.open_count_for(project.user)).to eq(1)
      expect(summary.open_count_for(member)).to eq(1)
      expect(summary.assigned_open_count).to eq(2)
      expect(summary.unassigned_open_count).to eq(1)
      expect(summary.total_open_count).to eq(3)
    end
  end
end

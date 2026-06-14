# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorGroup, type: :model do
  let(:project) { projects(:one) }
  let(:api_key) { api_keys(:one) }

  describe "associations" do
    it "belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end

    it "belongs to latest_event (IngestEvent) optional" do
      a = described_class.reflect_on_association(:latest_event)
      expect(a.macro).to eq(:belongs_to)
      expect(a.class_name).to eq("IngestEvent")
      expect(a.options[:optional]).to be true
    end

    it "belongs to assignee and assigned_by users optionally" do
      assignee = described_class.reflect_on_association(:assignee)
      assigned_by = described_class.reflect_on_association(:assigned_by)

      expect(assignee.macro).to eq(:belongs_to)
      expect(assignee.class_name).to eq("User")
      expect(assignee.options[:optional]).to be true
      expect(assigned_by.macro).to eq(:belongs_to)
      expect(assigned_by.class_name).to eq("User")
      expect(assigned_by.options[:optional]).to be true
    end

    it "has many error_occurrences dependent destroy" do
      a = described_class.reflect_on_association(:error_occurrences)
      expect(a.macro).to eq(:has_many)
      expect(a.options[:dependent]).to eq(:destroy)
    end

    it "has many ingest_events through error_occurrences" do
      a = described_class.reflect_on_association(:ingest_events)
      expect(a.macro).to eq(:has_many)
      expect(a.options[:through]).to eq(:error_occurrences)
    end
  end

  describe "scopes" do
    it "open returns unresolved" do
      group = create(:error_group, :with_occurrence, project: project, api_key: api_key)
      expect(described_class.open).to include(group)
      group.mark_resolved!
      expect(described_class.open).not_to include(group)
    end
  end

  describe "lifecycle transitions" do
    it "mark_resolved! sets status and resolved_at" do
      group = create(:error_group, :with_occurrence, project: project, api_key: api_key)
      group.mark_resolved!
      expect(group.reload).to be_resolved
      expect(group.resolved_at).to be_present
    end

    it "ignore! sets status and ignored_at" do
      group = create(:error_group, :with_occurrence, project: project, api_key: api_key)
      group.ignore!
      expect(group.reload).to be_ignored
      expect(group.ignored_at).to be_present
    end

    it "archive! sets status and archived_at" do
      group = create(:error_group, :with_occurrence, project: project, api_key: api_key)
      group.archive!
      expect(group.reload).to be_archived
    end

    it "reopen! clears resolved/ignored/archived and increments reopen_count" do
      group = create(:error_group, :with_occurrence, project: project, api_key: api_key)
      group.mark_resolved!
      group.reopen!
      group.reload
      expect(group).to be_unresolved
      expect(group.resolved_at).to be_nil
      expect(group.reopen_count).to eq(1)
    end
  end

  describe "assignment" do
    it "assigns an error group to the project owner" do
      group = create(:error_group, project: project)

      group.assign_to!(project.user, assigned_by: project.user)

      expect(group.reload.assignee).to eq(project.user)
      expect(group.assigned_by).to eq(project.user)
      expect(group.assigned_at).to be_present
    end

    it "assigns an error group to a project member" do
      member = create(:user)
      create(:project_membership, project: project, user: member)
      group = create(:error_group, project: project)

      group.assign_to!(member, assigned_by: project.user)

      expect(group.reload.assignee).to eq(member)
    end

    it "rejects assignment to a user without project access" do
      group = create(:error_group, project: project)
      outsider = create(:user)

      group.assignee = outsider

      expect(group).not_to be_valid
      expect(group.errors[:assignee]).to include("must have access to this project")
    end

    it "clears an assignment" do
      group = create(:error_group, project: project, assignee: project.user, assigned_by: project.user, assigned_at: Time.current)

      group.clear_assignment!

      expect(group.reload.assignee).to be_nil
      expect(group.assigned_by).to be_nil
      expect(group.assigned_at).to be_nil
    end
  end

  describe "#trend" do
    it "returns array of daily occurrence counts for the last N days" do
      group = create(:error_group, :with_occurrence, project: project, api_key: api_key)
      trend = group.trend(days: 7)
      expect(trend).to be_an(Array)
      expect(trend.size).to eq(7)
      expect(trend).to all(be_a(Integer))
    end
  end

  describe "factory" do
    it "builds a valid error group" do
      group = build(:error_group, project: project)

      expect(group).to be_valid
      expect(group.project).to eq(project)
    end

    it "creates a realistic grouped error with an occurrence" do
      group = create(:error_group, :with_occurrence, project: project, api_key: api_key)

      expect(group).to be_persisted
      expect(group.latest_event).to be_present
      expect(group.error_occurrences.count).to eq(1)
      expect(group.occurrence_count).to eq(1)
      expect(group.latest_event.project).to eq(project)
      expect(group.latest_event_occurred_at).to be_within(1.second).of(group.latest_event.occurred_at)
    end
  end
end

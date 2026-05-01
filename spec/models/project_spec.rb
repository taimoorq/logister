# frozen_string_literal: true

require "rails_helper"

RSpec.describe Project, type: :model do
  describe "associations" do
    it "belongs to user" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
    end

    it "has many api_keys dependent destroy" do
      a = described_class.reflect_on_association(:api_keys)
      expect(a.macro).to eq(:has_many)
      expect(a.options[:dependent]).to eq(:destroy)
    end

    it "has many ingest_events dependent destroy" do
      a = described_class.reflect_on_association(:ingest_events)
      expect(a.macro).to eq(:has_many)
      expect(a.options[:dependent]).to eq(:destroy)
    end

    it "has many error_groups dependent destroy" do
      a = described_class.reflect_on_association(:error_groups)
      expect(a.macro).to eq(:has_many)
      expect(a.options[:dependent]).to eq(:destroy)
    end

    it "has many project_memberships dependent destroy" do
      a = described_class.reflect_on_association(:project_memberships)
      expect(a.macro).to eq(:has_many)
      expect(a.options[:dependent]).to eq(:destroy)
    end

    it "has many members through project_memberships" do
      a = described_class.reflect_on_association(:members)
      expect(a.macro).to eq(:has_many)
      expect(a.options[:through]).to eq(:project_memberships)
      expect(a.options[:source]).to eq(:user)
    end
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

    it "defaults integration_kind to ruby" do
      project = Project.create!(user: users(:one), name: "Integration App")
      expect(project.integration_kind).to eq("ruby")
      expect(project.integration_label).to eq("Ruby gem")
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

  describe ".integration_options" do
    it "includes ruby, cfml, javascript, python, and .NET integrations" do
      expect(described_class.integration_options).to include(
        [ "Ruby gem", "ruby" ],
        [ ".NET / ASP.NET Core (logister-dotnet)", "dotnet" ],
        [ "CFML", "cfml" ],
        [ "JavaScript / TypeScript (logister-js)", "javascript" ],
        [ "Python (logister-python)", "python" ]
      )
    end
  end

  describe ".stats_for" do
    it "returns empty hash when project_ids blank" do
      expect(described_class.stats_for([])).to eq({})
      expect(described_class.stats_for(nil)).to eq({})
    end

    it "returns per-project stats with total_events, open_groups, trend" do
      ids = [ projects(:one).id ]
      stats = described_class.stats_for(ids)
      expect(stats).to be_a(Hash)
      expect(stats[ids.first]).to include(:total_events, :activity_events, :open_groups, :all_groups, :trend)
      expect(stats[ids.first][:trend].size).to eq(7)
    end

    it "counts non-error activity events and uses raw events for the 7-day trend" do
      travel_to Time.zone.local(2026, 4, 30, 12, 0, 0) do
        project = create(:project, :dotnet, user: users(:one))
        api_key = create(:api_key, project: project, user: users(:one))

        create(:ingest_event, :transaction, project: project, api_key: api_key, occurred_at: 2.days.ago)
        create(:ingest_event, :log, project: project, api_key: api_key, occurred_at: 1.day.ago)

        stats = described_class.stats_for([ project.id ]).fetch(project.id)

        expect(stats[:total_events]).to eq(2)
        expect(stats[:activity_events]).to eq(2)
        expect(stats[:open_groups]).to eq(0)
        expect(stats[:all_groups]).to eq(0)
        expect(stats[:trend].sum).to eq(2)
      end
    end
  end

  describe ".stats_cache_version" do
    it "returns empty array when project_ids blank" do
      expect(described_class.stats_cache_version([])).to eq([])
    end

    it "returns array of three integers for project_ids" do
      ids = [ projects(:one).id ]
      version = described_class.stats_cache_version(ids)
      expect(version).to be_an(Array)
      expect(version.size).to eq(3)
      expect(version).to all(be_a(Integer))
    end
  end
end

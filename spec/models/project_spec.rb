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

    it "has many GitHub installations through project links" do
      a = described_class.reflect_on_association(:github_installations)
      expect(a.macro).to eq(:has_many)
      expect(a.options[:through]).to eq(:project_github_installations)
    end
  end

  describe "validations" do
    it "validates presence of name and auto-managed identifiers" do
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

    it "does not allow integration_kind to change after creation" do
      project = Project.create!(user: users(:one), name: "Locked Integration App", integration_kind: "android")

      project.integration_kind = "ios"

      expect(project).not_to be_valid
      expect(project.errors[:integration_kind]).to include("cannot be changed after project creation")
    end

    it "allows blank project-level public API rate limit overrides" do
      project = Project.new(user: users(:one), name: "Rate Limit Defaults")
      expect(project).to be_valid
    end

    it "requires positive integer project-level public API rate limit overrides" do
      project = Project.new(
        user: users(:one),
        name: "Bad Rate Limits",
        public_api_rate_limit_requests_override: 0,
        public_api_rate_limit_period_seconds_override: 0,
        public_api_auth_failure_rate_limit_requests_override: 0
      )

      expect(project).not_to be_valid
      expect(project.errors[:public_api_rate_limit_requests_override]).to be_present
      expect(project.errors[:public_api_rate_limit_period_seconds_override]).to be_present
      expect(project.errors[:public_api_auth_failure_rate_limit_requests_override]).to be_present
    end
  end

  describe "public API rate limit overrides" do
    it "falls back to global defaults when project overrides are blank" do
      project = projects(:one)

      expect(project.public_api_rate_limit_requests_effective(1200)).to eq(1200)
      expect(project.public_api_rate_limit_period_seconds_effective(60)).to eq(60)
      expect(project.public_api_auth_failure_rate_limit_requests_effective(120)).to eq(120)
    end

    it "returns project overrides when present" do
      project = projects(:one)
      project.public_api_rate_limit_requests_override = 500
      project.public_api_rate_limit_period_seconds_override = 30
      project.public_api_auth_failure_rate_limit_requests_override = 40

      expect(project.public_api_rate_limit_requests_effective(1200)).to eq(500)
      expect(project.public_api_rate_limit_period_seconds_effective(60)).to eq(30)
      expect(project.public_api_auth_failure_rate_limit_requests_effective(120)).to eq(40)
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

  describe ".manageable_by" do
    it "includes projects owned by the user" do
      expect(Project.manageable_by(users(:one))).to include(projects(:one))
    end

    it "includes projects where the user is an admin" do
      project_memberships(:one).update!(role: :admin)

      expect(Project.manageable_by(users(:two))).to include(projects(:one))
    end

    it "excludes projects where the user is only a viewer" do
      expect(Project.manageable_by(users(:two))).not_to include(projects(:one))
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

  describe "#managed_by?" do
    it "returns true for owners" do
      expect(projects(:one).managed_by?(users(:one))).to be true
    end

    it "returns true for project admins" do
      project_memberships(:one).update!(role: :admin)

      expect(projects(:one).managed_by?(users(:two))).to be true
    end

    it "returns false for viewers" do
      expect(projects(:one).managed_by?(users(:two))).to be false
    end
  end

  describe "#assignable_users" do
    it "includes the owner and project members" do
      project = create(:project, user: users(:one))
      member = create(:user)
      outsider = create(:user)
      create(:project_membership, project: project, user: member)

      expect(project.assignable_users).to include(users(:one), member)
      expect(project.assignable_users).not_to include(outsider)
      expect(project.assignable_user?(users(:one))).to be true
      expect(project.assignable_user?(member)).to be true
      expect(project.assignable_user?(outsider)).to be false
    end
  end

  describe "archive lifecycle" do
    it "moves projects between active and archived scopes and revokes active api keys" do
      project = create(:project, user: users(:one))
      api_key = create(:api_key, project: project, user: users(:one))

      expect(described_class.active).to include(project)
      expect(described_class.archived).not_to include(project)

      project.archive!
      expect(project.reload).to be_archived
      expect(api_key.reload.revoked_at).to be_present
      expect(described_class.active).not_to include(project)
      expect(described_class.archived).to include(project)

      project.restore!
      expect(project.reload).not_to be_archived
      expect(api_key.reload.revoked_at).to be_present
      expect(described_class.active).to include(project)
    end
  end

  describe "#to_param" do
    it "returns uuid" do
      expect(projects(:one).to_param).to eq(projects(:one).uuid)
    end
  end

  describe ".integration_options" do
    it "orders Manual / HTTP API first and CFML last" do
      expect(described_class.integration_options).to eq([
        [ "Manual / HTTP API (custom client)", "http_api" ],
        [ "Cloudflare Pages", "cloudflare_pages" ],
        [ "Android app (logister-android)", "android" ],
        [ "iOS app (logister-ios)", "ios" ],
        [ "Ruby gem", "ruby" ],
        [ ".NET / ASP.NET Core (logister-dotnet)", "dotnet" ],
        [ "JavaScript / TypeScript (logister-js)", "javascript" ],
        [ "Python (logister-python)", "python" ],
        [ "CFML", "cfml" ]
      ])
    end
  end

  describe ".stats_for" do
    it "returns empty hash when project_ids blank" do
      expect(described_class.stats_for([])).to eq({})
      expect(described_class.stats_for(nil)).to eq({})
    end

    it "returns per-project recent stats with total_events, open_groups, trend" do
      ids = [ projects(:one).id ]
      stats = described_class.stats_for(ids)
      expect(stats).to be_a(Hash)
      expect(stats[ids.first]).to include(:total_events, :activity_events, :open_groups, :all_groups, :latest_event_at, :trend)
      expect(stats[ids.first][:trend].size).to eq(7)
      expect { Marshal.dump(stats) }.not_to raise_error
    end

    it "counts recent non-error activity events and uses raw events for the 7-day trend" do
      travel_to Time.zone.local(2026, 4, 30, 12, 0, 0) do
        project = create(:project, :dotnet, user: users(:one))
        api_key = create(:api_key, project: project, user: users(:one))

        create(:ingest_event, :transaction, project: project, api_key: api_key, occurred_at: 10.days.ago)
        create(:ingest_event, :transaction, project: project, api_key: api_key, occurred_at: 2.days.ago)
        create(:ingest_event, :log, project: project, api_key: api_key, occurred_at: 1.day.ago)

        stats = described_class.stats_for([ project.id ]).fetch(project.id)

        expect(stats[:total_events]).to eq(2)
        expect(stats[:activity_events]).to eq(2)
        expect(stats[:open_groups]).to eq(0)
        expect(stats[:all_groups]).to eq(0)
        expect(stats[:latest_event_at]).to be_within(1.second).of(1.day.ago)
        expect(stats[:trend].sum).to eq(2)
      end
    end
  end

  describe ".latest_event_at_by_project" do
    it "returns the newest event time for each project without entries for quiet projects" do
      loud_project = create(:project, user: users(:one))
      quiet_project = create(:project, user: users(:one))
      api_key = create(:api_key, project: loud_project, user: users(:one))
      create(:ingest_event, :log, project: loud_project, api_key: api_key, occurred_at: 2.days.ago)
      latest = create(:ingest_event, :transaction, project: loud_project, api_key: api_key, occurred_at: 1.hour.ago)

      latest_events = described_class.latest_event_at_by_project([ loud_project.id, quiet_project.id, "not-an-id" ])

      expect(latest_events.keys).to contain_exactly(loud_project.id)
      expect(latest_events[loud_project.id]).to be_within(1.second).of(latest.occurred_at)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe TelemetryIdempotencyKey, type: :model do
  describe ".for_source_references" do
    it "matches exact project-scoped identities with a flat composite predicate" do
      project = create(:project)
      other_project = create(:project)
      recorded_at = Time.zone.parse("2026-08-11 10:00:00")
      matching = create_key(project: project, record_id: 42, recorded_at: recorded_at)
      create_key(project: project, record_id: 42, recorded_at: recorded_at + 1.second)
      create_key(project: other_project, record_id: 42, recorded_at: recorded_at)
      references = 999.times.map do |index|
        { id: 10_000_000 + index, occurred_at: recorded_at }
      end
      references << { id: 42, occurred_at: recorded_at }

      relation = described_class.for_source_references(
        project_id: project.id,
        record_type: "IngestEvent",
        references: references,
        id_key: :id,
        recorded_at_key: :occurred_at
      )

      expect(relation.to_sql).to include(" IN (")
      expect(relation.to_sql).not_to include(" OR ")
      expect(relation).to contain_exactly(matching)
    end
  end

  def create_key(project:, record_id:, recorded_at:)
    described_class.create!(
      project: project,
      client_identifier: SecureRandom.uuid,
      signal: "log",
      record_type: "IngestEvent",
      record_id: record_id,
      recorded_at: recorded_at,
      expires_at: recorded_at + described_class::RETENTION
    )
  end
end

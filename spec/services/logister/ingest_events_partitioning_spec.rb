# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::IngestEventsPartitioning do
  describe "post-cutover operation" do
    it "reports the deployed partitioned table and retained backup" do
      create(:ingest_event, :log)

      result = described_class.new.status

      expect(result).to include(
        phase: "post_cutover",
        ingest_events_partitioned: true,
        backup_table_exists: true,
        old_shadow_table_exists: false,
        mirror_trigger_installed: false
      )
      expect(result[:ingest_events]).to be_a(Integer)
      expect(result[:partitions]).not_to be_empty
    end

    it "validates the retained cutover copy through the post-cutover path" do
      result = described_class.new.validate

      expect(result).to include(:valid, :missing_in_shadow, :extra_in_shadow, :mismatched_rows, :months)
    end

    it "refuses historical backfill and a repeated cutover with clear errors" do
      partitioning = described_class.new

      expect { partitioning.backfill(dry_run: true) }
        .to raise_error(described_class::CutoverError, /unavailable after cutover/)
      expect { partitioning.cutover }
        .to raise_error(described_class::CutoverError, /already complete/)
    end

    it "keeps post-cutover reference constraints valid" do
      result = described_class.new.validate_cutover_constraints

      expect(result.fetch(:reference_constraints).pluck(:new_exists)).to all(be(true))
      expect(result.fetch(:reference_constraints).pluck(:new_validated)).to all(be(true))
    end

    it "maintains future partitions idempotently" do
      partitioning = described_class.new

      first = partitioning.ensure_future_partitions(months_ahead: 12)
      second = partitioning.ensure_future_partitions(months_ahead: 12)

      expect(first.fetch(:partitioned_tables)).to include("public.ingest_events")
      expect(second.fetch(:created_partitions)).to be_empty
    end
  end
end

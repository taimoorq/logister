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
      expect(second.fetch(:default_partitions).first).to include(:partition, :row_count, :drain_ready, :month_buckets)
    end

    it "makes rows routed to the default partition visible for a drain" do
      create(:ingest_event, occurred_at: Time.zone.parse("2035-04-15T12:00:00Z"))

      result = described_class.new.partition_maintenance_status(months_ahead: 1)
      default_partition = result.fetch(:default_partitions).find { |entry| entry.fetch(:parent) == "public.ingest_events" }

      expect(default_partition).to include(drain_ready: false)
      expect(default_partition.fetch(:row_count)).to be >= 1
      expect(default_partition.fetch(:month_buckets)).to include(hash_including("month" => "2035-04"))
    end
  end

  describe "expired partitions" do
    let(:now) { Time.zone.parse("2026-11-06 12:00:00") }

    def partition_attached?(name)
      ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT EXISTS (
          SELECT 1 FROM pg_inherits
          WHERE inhparent = 'public.ingest_events'::regclass
            AND inhrelid = to_regclass(#{ActiveRecord::Base.connection.quote("public.#{name}")})
        )
      SQL
    end

    it "drops empty months past the longest retention window and keeps months with rows" do
      project = create(:project)
      create(:project_retention_policy, project: project, hot_retention_days: 90)
      open_error = create(:ingest_event, project: project, occurred_at: Time.zone.parse("2026-03-10 12:00:00"))

      result = described_class.new.retire_expired_partitions(now: now)

      retired = result.fetch(:retired_partitions).pluck(:partition)
      expect(retired).to include("public.ingest_events_partitioned_2026_04", "public.ingest_events_partitioned_2026_07")
      expect(retired).not_to include("public.ingest_events_partitioned_2026_03", "public.ingest_events_partitioned_2026_08")
      expect(result.fetch(:skipped_partitions)).to include(
        hash_including(partition: "public.ingest_events_partitioned_2026_03", reason: "rows_present")
      )
      expect(partition_attached?("ingest_events_partitioned_2026_04")).to be(false)
      expect(ActiveRecord::Base.connection.select_value("SELECT to_regclass('public.ingest_events_partitioned_2026_04')")).to be_nil
      expect(partition_attached?("ingest_events_partitioned_2026_03")).to be(true)
      expect(partition_attached?("ingest_events_partitioned_2026_08")).to be(true)
      expect(IngestEvent.exists?(open_error.id)).to be(true)
    end

    it "keeps every partition while the longest retention window still covers it" do
      create(:project_retention_policy, project: create(:project), hot_retention_days: 365)

      partitioning = described_class.new

      expect(partitioning.expired_partitions(now: now)).to be_empty
      expect(partitioning.retire_expired_partitions(now: now).fetch(:retired_partitions)).to be_empty
      expect(partition_attached?("ingest_events_partitioned_2026_04")).to be(true)
    end

    it "only reports what a dry run would retire" do
      result = described_class.new.retire_expired_partitions(now: now, dry_run: true)

      expect(result.fetch(:retired_partitions)).to include(
        hash_including(partition: "public.ingest_events_partitioned_2026_04", dry_run: true)
      )
      expect(partition_attached?("ingest_events_partitioned_2026_04")).to be(true)
    end

    it "skips a partition when the parent lock is not available in time" do
      partitioning = described_class.new
      allow(partitioning).to receive(:execute).and_call_original
      allow(partitioning).to receive(:execute).with(/LOCK TABLE ONLY public.ingest_events/)
                                              .and_raise(ActiveRecord::LockWaitTimeout)

      result = partitioning.retire_expired_partitions(now: now)

      expect(result.fetch(:retired_partitions)).to be_empty
      expect(result.fetch(:skipped_partitions)).to include(
        hash_including(partition: "public.ingest_events_partitioned_2026_04", reason: "lock_unavailable")
      )
      expect(partition_attached?("ingest_events_partitioned_2026_04")).to be(true)
    end

    it "reports sparse expired partitions for compaction and refuses partitions inside the window" do
      stub_const("#{described_class}::RETIREMENT_MAX_HEAP_BYTES", -1)
      stub_const("#{described_class}::COMPACTION_MIN_RECLAIMABLE_BYTES", 1)
      partitioning = described_class.new

      candidates = partitioning.compaction_candidates(now: now).pluck(:name)
      plan = partitioning.compact_partition("ingest_events_partitioned_2026_04", now: now)

      expect(candidates).to include("public.ingest_events_partitioned_2026_04")
      expect(candidates).not_to include("public.ingest_events_partitioned_2026_10")
      expect(plan).to include(name: "public.ingest_events_partitioned_2026_04", month: "2026-04", dry_run: true)
      expect { partitioning.compact_partition("ingest_events_partitioned_2026_10", now: now) }
        .to raise_error(described_class::CutoverError, /past every project's retention window/)
      expect { partitioning.compact_partition("ingest_events_partitioned_default", now: now) }
        .to raise_error(described_class::CutoverError)
    end

    it "holds compaction while a retention run may still delete rows from expired months" do
      stub_const("#{described_class}::RETIREMENT_MAX_HEAP_BYTES", -1)
      stub_const("#{described_class}::COMPACTION_MIN_RECLAIMABLE_BYTES", 1)
      create(:project_retention_run, status: "running", dry_run: false)
      partitioning = described_class.new

      april = partitioning.expired_partitions(now: now).find { |partition| partition.fetch(:month) == "2026-04" }

      expect(april.fetch(:recommended_action)).to eq("wait_for_retention")
      expect(partitioning.compaction_candidates(now: now)).to be_empty
    end
  end

  describe "expired partition compaction" do
    # VACUUM cannot run inside the example transaction. The example rewrites an
    # existing partition in place and writes no rows, so there is nothing to clean up.
    self.use_transactional_tests = false

    it "rewrites an expired partition and restores the session timeouts" do
      connection = ActiveRecord::Base.connection
      lock_timeout = connection.select_value("SHOW lock_timeout")
      statement_timeout = connection.select_value("SHOW statement_timeout")

      result = described_class.new.compact_partition(
        "ingest_events_partitioned_2026_04",
        now: Time.zone.parse("2026-11-06 12:00:00"),
        dry_run: false
      )

      expect(result).to include(name: "public.ingest_events_partitioned_2026_04", dry_run: false)
      expect(result.fetch(:total_bytes_after)).to be_a(Integer)
      expect(connection.select_value("SHOW lock_timeout")).to eq(lock_timeout)
      expect(connection.select_value("SHOW statement_timeout")).to eq(statement_timeout)
    end
  end
end

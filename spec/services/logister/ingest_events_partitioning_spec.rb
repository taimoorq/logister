# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::IngestEventsPartitioning do
  after(:context) do
    ActiveRecord::Base.connection.reconnect!
  end

  describe "#status" do
    it "reports pre-cutover mirror counts" do
      create(:ingest_event, :log)

      result = described_class.new.status

      expect(result[:phase]).to eq("pre_cutover")
      expect(result[:source_events]).to be_a(Integer)
      expect(result[:shadow_events]).to be_a(Integer)
      expect(result[:missing_in_shadow]).to be_a(Integer)
      expect(result[:extra_in_shadow]).to be_a(Integer)
      expect(result[:mismatched_rows]).to be_a(Integer)
    end
  end

  describe "#backfill" do
    it "restores missing shadow rows" do
      event = create(:ingest_event, :log, message: "Backfill me")
      delete_shadow_row(event)

      result = described_class.new.backfill(batch_size: 1, dry_run: false)

      expect(result[:upserted_rows]).to be_positive
      expect(shadow_row_for(event)).to include("message" => "Backfill me")
    end
  end

  describe "#validate" do
    it "reports missing shadow rows" do
      event = create(:ingest_event, :log)
      delete_shadow_row(event)

      result = described_class.new.validate

      expect(result[:valid]).to be false
      expect(result[:missing_in_shadow]).to be_positive
    end
  end

  describe "#cutover" do
    it "swaps the logical ingest_events table to the partitioned copy" do
      event = create(:ingest_event, :log, message: "Cutover keeps me")
      partitioning = described_class.new
      prepare_partition_cutover!(partitioning)

      result = partitioning.cutover(lock_timeout: "5s")

      expect(result[:cutover_complete]).to be true
      expect(partitioned_table?("public.ingest_events")).to be true
      expect(table_exists?("public.ingest_events_unpartitioned_backup")).to be true
      expect(table_exists?("public.ingest_events_partitioned")).to be false
      expect(IngestEvent.find(event.id).message).to eq("Cutover keeps me")
      expect(partitioning.validate_cutover_copy.fetch(:valid)).to be true

      IngestEvent.reset_column_information
      expect(IngestEvent.primary_key).to eq("id")
      IngestEvent.find(event.id).destroy!
      expect(IngestEvent.where(id: event.id)).to be_empty

      constraints = cutover_constraint_rows
      expect(constraints.map { |row| row.fetch("conname") }).to contain_exactly(
        "fk_check_in_monitors_last_event_partition_ref",
        "fk_error_groups_latest_event_partition_ref",
        "fk_error_occurrences_ingest_event_partition_ref"
      )
      expect(constraints.map { |row| row.fetch("convalidated") }).to all(be(false))
    end

    it "validates post-cutover composite foreign keys on demand" do
      create(:ingest_event, :log)
      partitioning = described_class.new
      prepare_partition_cutover!(partitioning)

      partitioning.cutover(lock_timeout: "5s")
      result = partitioning.validate_cutover_constraints

      expect(result.fetch(:reference_constraints).pluck(:new_validated)).to all(be(true))
    end
  end

  def delete_shadow_row(event)
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      DELETE FROM public.ingest_events_partitioned
      WHERE id = #{Integer(event.id)}
        AND occurred_at = #{ActiveRecord::Base.connection.quote(event.occurred_at)}
    SQL
  end

  def shadow_row_for(event)
    ActiveRecord::Base.connection.select_one(<<~SQL.squish)
      SELECT id, message
      FROM public.ingest_events_partitioned
      WHERE id = #{Integer(event.id)}
        AND occurred_at = #{ActiveRecord::Base.connection.quote(event.occurred_at)}
    SQL
  end

  def prepare_partition_cutover!(partitioning)
    backfill_reference_timestamps
    partitioning.backfill(dry_run: false)
  end

  def backfill_reference_timestamps
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      UPDATE public.error_occurrences target
      SET ingest_event_occurred_at = ingest_events.occurred_at
      FROM public.ingest_events
      WHERE target.ingest_event_id = ingest_events.id
        AND target.ingest_event_occurred_at IS NULL
    SQL
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      UPDATE public.error_groups target
      SET latest_event_occurred_at = ingest_events.occurred_at
      FROM public.ingest_events
      WHERE target.latest_event_id = ingest_events.id
        AND target.latest_event_occurred_at IS NULL
    SQL
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      UPDATE public.check_in_monitors target
      SET last_event_occurred_at = ingest_events.occurred_at
      FROM public.ingest_events
      WHERE target.last_event_id = ingest_events.id
        AND target.last_event_occurred_at IS NULL
    SQL
  end

  def table_exists?(table_name)
    ActiveRecord::Base.connection.select_value("SELECT to_regclass(#{ActiveRecord::Base.connection.quote(table_name)}) IS NOT NULL")
  end

  def partitioned_table?(table_name)
    ActiveRecord::Base.connection.select_value(<<~SQL.squish)
      SELECT EXISTS (
        SELECT 1
        FROM pg_partitioned_table
        WHERE partrelid = #{ActiveRecord::Base.connection.quote(table_name)}::regclass
      )
    SQL
  end

  def cutover_constraint_rows
    ActiveRecord::Base.connection.select_all(<<~SQL.squish).to_a
      SELECT conname, convalidated
      FROM pg_constraint
      WHERE conname IN (
        'fk_check_in_monitors_last_event_partition_ref',
        'fk_error_groups_latest_event_partition_ref',
        'fk_error_occurrences_ingest_event_partition_ref'
      )
      ORDER BY conname
    SQL
  end
end

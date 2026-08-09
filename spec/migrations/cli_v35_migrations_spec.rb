# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260809120000_add_uuid_to_check_in_monitors")
require Rails.root.join("db/migrate/20260809121000_add_cli_event_cursor_indexes")

RSpec.describe "CLI v3.5 migrations" do
  describe AddCliEventCursorIndexes do
    subject(:migration) { described_class.new }

    it "preserves a compatible incomplete partitioned parent on retry" do
      allow(migration).to receive(:index_present?).with("idx_ie_cli_occurred_uuid").and_return(true)
      allow(migration).to receive(:index_definition_compatible?).and_return(true)

      expect(migration).not_to receive(:execute)

      migration.send(
        :ensure_partitioned_parent_index!,
        "idx_ie_cli_occurred_uuid",
        described_class::INDEXES.fetch("idx_ie_cli_occurred_uuid")
      )
    end

    it "fails safely instead of cascade-dropping an incompatible parent" do
      allow(migration).to receive(:index_present?).and_return(true)
      allow(migration).to receive(:index_definition_compatible?).and_return(false)

      expect(migration).not_to receive(:execute)
      expect do
        migration.send(
          :ensure_partitioned_parent_index!,
          "idx_ie_cli_occurred_uuid",
          described_class::INDEXES.fetch("idx_ie_cli_occurred_uuid")
        )
      end.to raise_error(ActiveRecord::MigrationError, /incompatible definition/)
    end

    it "asserts that every current leaf is attached and the parent is valid" do
      allow(migration).to receive(:partition_names).and_return(%w[partition_one partition_two])
      allow(migration).to receive(:attached_partition_indexes).and_return([ "public.child_one" ])
      allow(migration).to receive(:valid_index?).and_return(true)

      expect do
        migration.send(:assert_partitioned_index_complete!, "idx_ie_cli_occurred_uuid")
      end.to raise_error(ActiveRecord::MigrationError, /1\/2 leaf indexes attached/)
    end

    it "retains additive partition indexes during application rollback" do
      expect(migration).not_to receive(:execute)

      migration.down
    end

    it "bounds lock waits and restores the session setting when a resumable step fails" do
      expect(migration).to receive(:execute).with("SET lock_timeout = '5s'").ordered
      expect(migration).to receive(:execute).with("RESET lock_timeout").ordered

      expect do
        migration.send(:with_lock_timeout) { raise ActiveRecord::LockWaitTimeout, "busy partition" }
      end.to raise_error(ActiveRecord::LockWaitTimeout, "busy partition")
    end
  end

  describe AddUuidToCheckInMonitors do
    subject(:migration) { described_class.new }

    it "never removes issued monitor UUID identities during rollback" do
      allow(migration).to receive(:index_exists?).and_return(false)
      allow(migration).to receive(:execute)

      expect(migration).not_to receive(:remove_column).with(:check_in_monitors, :uuid)
      expect(migration).not_to receive(:remove_index).with(:check_in_monitors, :uuid, anything)

      migration.down
    end

    it "fails safely when a valid same-name index has the wrong definition" do
      allow(migration).to receive(:index_present?).and_return(true)
      allow(migration).to receive(:index_exists?).and_return(false)
      allow(migration).to receive(:valid_index?).and_return(true)

      expect do
        migration.send(
          :ensure_concurrent_index!,
          :check_in_monitors,
          :uuid,
          name: "index_check_in_monitors_on_uuid",
          unique: true
        ) { raise "must not create" }
      end.to raise_error(ActiveRecord::MigrationError, /incompatible definition/)
    end
  end
end

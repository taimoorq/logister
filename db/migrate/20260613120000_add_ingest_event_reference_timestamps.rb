class AddIngestEventReferenceTimestamps < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BATCH_SIZE = 10_000

  def up
    add_reference_timestamp_columns
    backfill_reference_timestamps
    add_reference_timestamp_indexes
  end

  def down
    remove_reference_timestamp_indexes
    remove_column :check_in_monitors, :last_event_occurred_at if column_exists?(:check_in_monitors, :last_event_occurred_at)
    remove_column :error_groups, :latest_event_occurred_at if column_exists?(:error_groups, :latest_event_occurred_at)
    remove_column :error_occurrences, :ingest_event_occurred_at if column_exists?(:error_occurrences, :ingest_event_occurred_at)
  end

  private

  def add_reference_timestamp_columns
    add_column :error_occurrences, :ingest_event_occurred_at, :datetime unless column_exists?(:error_occurrences, :ingest_event_occurred_at)
    add_column :error_groups, :latest_event_occurred_at, :datetime unless column_exists?(:error_groups, :latest_event_occurred_at)
    add_column :check_in_monitors, :last_event_occurred_at, :datetime unless column_exists?(:check_in_monitors, :last_event_occurred_at)
  end

  def backfill_reference_timestamps
    backfill_table(
      table: :error_occurrences,
      id_column: :ingest_event_id,
      timestamp_column: :ingest_event_occurred_at,
      nullable_reference: false
    )
    backfill_table(
      table: :error_groups,
      id_column: :latest_event_id,
      timestamp_column: :latest_event_occurred_at,
      nullable_reference: true
    )
    backfill_table(
      table: :check_in_monitors,
      id_column: :last_event_id,
      timestamp_column: :last_event_occurred_at,
      nullable_reference: true
    )
  end

  def backfill_table(table:, id_column:, timestamp_column:, nullable_reference:)
    return unless column_exists?(table, timestamp_column)

    null_guard = nullable_reference ? "AND target.#{id_column} IS NOT NULL" : ""

    say_with_time "Backfilling #{table}.#{timestamp_column}" do
      loop do
        result = execute(<<~SQL.squish)
          WITH candidate_rows AS (
            SELECT target.id, ingest_events.occurred_at
            FROM #{table} target
            JOIN ingest_events ON ingest_events.id = target.#{id_column}
            WHERE target.#{timestamp_column} IS NULL
              #{null_guard}
            ORDER BY target.id
            LIMIT #{BATCH_SIZE}
          )
          UPDATE #{table} target
          SET #{timestamp_column} = candidate_rows.occurred_at
          FROM candidate_rows
          WHERE target.id = candidate_rows.id
        SQL

        break if result.cmd_tuples.zero?
      end
    end
  end

  def add_reference_timestamp_indexes
    add_index :error_occurrences,
              [ :ingest_event_id, :ingest_event_occurred_at ],
              name: "idx_error_occurrences_event_partition_ref",
              algorithm: :concurrently unless index_exists?(:error_occurrences, [ :ingest_event_id, :ingest_event_occurred_at ], name: "idx_error_occurrences_event_partition_ref")

    add_index :error_groups,
              [ :latest_event_id, :latest_event_occurred_at ],
              name: "idx_error_groups_latest_event_partition_ref",
              where: "latest_event_id IS NOT NULL",
              algorithm: :concurrently unless index_exists?(:error_groups, [ :latest_event_id, :latest_event_occurred_at ], name: "idx_error_groups_latest_event_partition_ref")

    add_index :check_in_monitors,
              [ :last_event_id, :last_event_occurred_at ],
              name: "idx_check_in_monitors_last_event_partition_ref",
              where: "last_event_id IS NOT NULL",
              algorithm: :concurrently unless index_exists?(:check_in_monitors, [ :last_event_id, :last_event_occurred_at ], name: "idx_check_in_monitors_last_event_partition_ref")
  end

  def remove_reference_timestamp_indexes
    remove_index :check_in_monitors, name: "idx_check_in_monitors_last_event_partition_ref", algorithm: :concurrently if index_exists?(:check_in_monitors, name: "idx_check_in_monitors_last_event_partition_ref")
    remove_index :error_groups, name: "idx_error_groups_latest_event_partition_ref", algorithm: :concurrently if index_exists?(:error_groups, name: "idx_error_groups_latest_event_partition_ref")
    remove_index :error_occurrences, name: "idx_error_occurrences_event_partition_ref", algorithm: :concurrently if index_exists?(:error_occurrences, name: "idx_error_occurrences_event_partition_ref")
  end
end

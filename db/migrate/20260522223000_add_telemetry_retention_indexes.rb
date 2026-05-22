class AddTelemetryRetentionIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ingest_events,
      [ :created_at, :id ],
      name: "idx_ingest_events_retention_created_id",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :trace_spans,
      [ :created_at, :id ],
      name: "idx_trace_spans_retention_created_id",
      algorithm: :concurrently,
      if_not_exists: true
  end
end

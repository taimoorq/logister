class AddDashboardExplorerIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ingest_events,
              [ :project_id, :event_type, :occurred_at ],
              name: "idx_ingest_events_project_occurred_type",
              order: { occurred_at: :desc },
              algorithm: :concurrently,
              if_not_exists: true

    add_index :ingest_events,
              "project_id, (COALESCE(NULLIF(context->>'environment', ''), 'unknown')), occurred_at DESC",
              name: "idx_ingest_events_project_environment_occurred",
              using: :btree,
              algorithm: :concurrently,
              if_not_exists: true
  end
end

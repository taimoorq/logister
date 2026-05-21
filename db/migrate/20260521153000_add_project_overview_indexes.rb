class AddProjectOverviewIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ingest_events,
              [ :project_id, :occurred_at ],
              order: { occurred_at: :desc },
              where: "event_type <> 0",
              name: "idx_ingest_events_project_activity_occurred",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :ingest_events,
              [ :project_id, :occurred_at ],
              order: { occurred_at: :desc },
              where: "event_type = 2",
              name: "idx_ingest_events_project_transactions_occurred",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :ingest_events,
              [ :project_id, :occurred_at ],
              order: { occurred_at: :desc },
              where: "event_type = 1 AND message = 'db.query'",
              name: "idx_ingest_events_project_db_query_occurred",
              algorithm: :concurrently,
              if_not_exists: true
  end
end

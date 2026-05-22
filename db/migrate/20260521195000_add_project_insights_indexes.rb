class AddProjectInsightsIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ingest_events,
              "project_id, (NULLIF(context->>'release', '')), occurred_at DESC",
              name: "idx_ingest_events_project_release_occurred",
              using: :btree,
              where: "COALESCE(context->>'release', '') <> ''",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :ingest_events,
              [ :project_id, :message, :occurred_at ],
              name: "idx_ingest_events_project_metric_message_occurred",
              order: { occurred_at: :desc },
              where: "event_type = 1",
              algorithm: :concurrently,
              if_not_exists: true
  end
end

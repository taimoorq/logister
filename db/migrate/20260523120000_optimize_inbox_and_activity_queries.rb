class OptimizeInboxAndActivityQueries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ingest_events,
              [ :project_id, :occurred_at, :id ],
              order: { occurred_at: :desc, id: :desc },
              where: "event_type <> 0",
              name: "idx_ingest_events_project_activity_cursor",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :ingest_events,
              "project_id, (COALESCE(NULLIF(context->>'environment', ''), 'production')), occurred_at DESC, id DESC",
              using: :btree,
              where: "event_type <> 0",
              name: "idx_ingest_events_activity_env_cursor",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :ingest_events,
              "project_id, (context->>'release'), occurred_at DESC, id DESC",
              using: :btree,
              where: "event_type <> 0 AND COALESCE(context->>'release', '') <> ''",
              name: "idx_ingest_events_activity_release_cursor",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :error_groups,
              [ :project_id, :assigned_user_id, :status, :last_seen_at, :id ],
              order: { last_seen_at: :desc, id: :desc },
              name: "idx_error_groups_project_assignee_seen_cursor",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :trace_spans,
              [ :project_id, :duration_ms, :started_at ],
              order: { duration_ms: :desc, started_at: :desc },
              where: "kind IN ('server', 'browser') AND (parent_span_id IS NULL OR parent_span_id = '')",
              name: "idx_trace_spans_project_root_duration",
              algorithm: :concurrently,
              if_not_exists: true
  end
end

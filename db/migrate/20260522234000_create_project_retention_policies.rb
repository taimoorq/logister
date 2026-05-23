class CreateProjectRetentionPolicies < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :project_retention_policies do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      t.integer :hot_retention_days, null: false, default: 30
      t.integer :trace_retention_days, null: false, default: 30
      t.integer :error_retention_days
      t.boolean :archive_enabled, null: false, default: false
      t.boolean :archive_before_delete, null: false, default: false
      t.datetime :last_archive_run_at
      t.datetime :last_retention_run_at
      t.jsonb :last_retention_result, null: false, default: {}
      t.timestamps
    end

    create_table :telemetry_archives do |t|
      t.references :project, null: false, foreign_key: true
      t.string :record_type, null: false
      t.string :scope, null: false
      t.string :status, null: false, default: "completed"
      t.datetime :before_at, null: false
      t.datetime :after_at
      t.integer :rows, null: false, default: 0
      t.bigint :bytes, null: false, default: 0
      t.jsonb :objects, null: false, default: []
      t.boolean :dry_run, null: false, default: false
      t.text :error_message
      t.timestamps
    end

    add_index :telemetry_archives,
              [ :project_id, :scope, :status, :before_at ],
              name: "idx_telemetry_archives_project_scope_status_before",
              order: { before_at: :desc },
              algorithm: :concurrently
    add_index :telemetry_archives,
              [ :project_id, :created_at ],
              name: "idx_telemetry_archives_project_created_at",
              order: { created_at: :desc },
              algorithm: :concurrently
    add_index :ingest_events,
              [ :project_id, :event_type, :occurred_at, :id ],
              name: "idx_ingest_events_project_type_retention",
              algorithm: :concurrently,
              if_not_exists: true
    add_index :trace_spans,
              [ :project_id, :started_at, :id ],
              name: "idx_trace_spans_project_retention",
              algorithm: :concurrently,
              if_not_exists: true
    add_index :error_groups,
              [ :project_id, :status, :last_seen_at, :id ],
              name: "idx_error_groups_project_retention",
              algorithm: :concurrently,
              if_not_exists: true
  end
end

# frozen_string_literal: true

class CreateProjectRetentionRuns < ActiveRecord::Migration[8.1]
  ACTIVE_STATUSES = %w[queued running waiting retrying].freeze

  def change
    create_table :project_retention_runs do |table|
      table.references :project,
                       null: false,
                       foreign_key: { on_delete: :cascade },
                       index: false
      table.string :run_key, null: false
      table.string :trigger_kind, null: false, default: "scheduled"
      table.boolean :dry_run, null: false, default: false
      table.datetime :scheduled_for, null: false
      table.string :status, null: false, default: "queued"
      table.string :phase, null: false, default: "planning"
      table.string :current_scope
      table.integer :attempts, null: false, default: 0
      table.bigint :fence_version, null: false, default: 0
      table.uuid :attempt_token
      table.integer :objects_total, null: false, default: 0
      table.integer :objects_completed, null: false, default: 0
      table.bigint :rows_total, null: false, default: 0
      table.bigint :rows_completed, null: false, default: 0
      table.datetime :available_at
      table.datetime :started_at
      table.datetime :heartbeat_at
      table.datetime :last_checkpoint_at
      table.datetime :recovery_enqueued_at
      table.datetime :completed_at
      table.datetime :failed_at
      table.datetime :cancelled_at
      table.datetime :last_error_at
      table.string :last_error_class
      table.text :last_error_message
      table.jsonb :policy_snapshot, null: false, default: {}
      table.jsonb :cutoff_snapshot, null: false, default: {}
      table.jsonb :result, null: false, default: {}
      table.jsonb :metadata, null: false, default: {}
      table.integer :lock_version, null: false, default: 0
      table.timestamps
    end

    add_index :project_retention_runs, :run_key, unique: true
    add_index :project_retention_runs,
              [ :project_id, :status, :scheduled_for ],
              name: "idx_retention_runs_project_status_schedule"
    add_index :project_retention_runs,
              [ :status, :heartbeat_at ],
              name: "idx_retention_runs_status_heartbeat"
    add_index :project_retention_runs,
              [ :status, :available_at ],
              name: "idx_retention_runs_status_available"
    add_index :project_retention_runs,
              :project_id,
              unique: true,
              where: "dry_run = FALSE AND status IN (#{ACTIVE_STATUSES.map { |status| connection.quote(status) }.join(', ')})",
              name: "idx_retention_runs_one_active_project"

    add_reference :telemetry_archives,
                  :project_retention_run,
                  null: true,
                  foreign_key: { on_delete: :nullify },
                  index: true

    change_table :telemetry_archive_objects, bulk: true do |table|
      table.string :source_cleanup_status, null: false, default: "pending"
      table.integer :source_cleanup_attempts, null: false, default: 0
      table.integer :source_deleted_rows, null: false, default: 0
      table.datetime :source_cleanup_started_at
      table.datetime :source_cleanup_verified_at
      table.datetime :source_cleanup_completed_at
      table.datetime :source_cleanup_failed_at
      table.string :source_cleanup_checksum_sha256
      table.text :source_cleanup_error
    end

    add_index :telemetry_archive_objects,
              [ :telemetry_archive_id, :source_cleanup_status, :sequence ],
              name: "idx_archive_objects_cleanup_progress"

    add_check_constraint :project_retention_runs,
                         "status IN ('queued', 'running', 'waiting', 'retrying', 'completed', 'failed', 'cancelled', 'superseded')",
                         name: "project_retention_runs_status"
    add_check_constraint :project_retention_runs,
                         "phase IN ('planning', 'enumerating', 'uploading', 'verifying', 'cleaning', 'finalizing')",
                         name: "project_retention_runs_phase"
    add_check_constraint :project_retention_runs,
                         "trigger_kind IN ('scheduled', 'manual', 'recovery', 'legacy')",
                         name: "project_retention_runs_trigger"
    add_check_constraint :project_retention_runs,
                         "attempts >= 0 AND fence_version >= 0 AND objects_total >= 0 AND objects_completed >= 0 AND rows_total >= 0 AND rows_completed >= 0",
                         name: "project_retention_runs_counts"
    add_check_constraint :project_retention_runs,
                         "objects_completed <= objects_total AND rows_completed <= rows_total",
                         name: "project_retention_runs_progress"
    add_check_constraint :telemetry_archive_objects,
                         "source_cleanup_status IN ('pending', 'cleaning', 'completed', 'blocked', 'failed', 'not_required')",
                         name: "telemetry_archive_objects_cleanup_status"
    add_check_constraint :telemetry_archive_objects,
                         "source_cleanup_attempts >= 0 AND source_deleted_rows >= 0 AND source_deleted_rows <= expected_rows",
                         name: "telemetry_archive_objects_cleanup_counts"

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE telemetry_archive_objects AS objects
          SET source_cleanup_status = 'completed',
              source_deleted_rows = objects.expected_rows,
              source_cleanup_completed_at = archives.source_deleted_at,
              updated_at = CURRENT_TIMESTAMP
          FROM telemetry_archives AS archives
          WHERE archives.id = objects.telemetry_archive_id
            AND archives.source_deleted_at IS NOT NULL
        SQL
      end
    end
  end
end

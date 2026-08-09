# frozen_string_literal: true

class ExpandTelemetryArchiveLifecycle < ActiveRecord::Migration[8.1]
  def change
    change_table :telemetry_archives, bulk: true do |table|
      table.integer :manifest_version, null: false, default: 1
      table.integer :expected_rows, null: false, default: 0
      table.bigint :expected_bytes, null: false, default: 0
      table.integer :verified_rows, null: false, default: 0
      table.bigint :verified_bytes, null: false, default: 0
      table.string :checksum_sha256
      table.bigint :source_min_id
      table.bigint :source_max_id
      table.datetime :exported_at
      table.datetime :upload_started_at
      table.datetime :uploaded_at
      table.datetime :verification_started_at
      table.datetime :verified_at
      table.datetime :completed_at
      table.datetime :failed_at
      table.datetime :restored_at
      table.datetime :source_deleted_at
      table.integer :source_deleted_rows, null: false, default: 0
      table.integer :retry_count, null: false, default: 0
      table.jsonb :lifecycle_metadata, null: false, default: {}
    end

    create_table :telemetry_archive_objects do |table|
      table.references :telemetry_archive,
                       null: false,
                       foreign_key: { on_delete: :cascade },
                       index: false
      table.integer :sequence, null: false
      table.string :status, null: false, default: "pending"
      table.string :object_key, null: false
      table.string :content_type, null: false, default: "application/jsonl+gzip"
      table.string :checksum_sha256, null: false
      table.string :checksum_md5_base64, null: false
      table.integer :expected_rows, null: false
      table.bigint :expected_bytes, null: false
      table.integer :verified_rows, null: false, default: 0
      table.bigint :verified_bytes, null: false, default: 0
      table.bigint :source_min_id, null: false
      table.bigint :source_max_id, null: false
      table.jsonb :source_references, null: false, default: []
      table.integer :attempts, null: false, default: 0
      table.datetime :uploaded_at
      table.datetime :verified_at
      table.datetime :deleted_at
      table.text :error_message
      table.timestamps
    end

    add_index :telemetry_archive_objects,
              [ :telemetry_archive_id, :sequence ],
              unique: true,
              name: "idx_telemetry_archive_objects_manifest_sequence"
    add_index :telemetry_archive_objects,
              :object_key,
              unique: true,
              name: "idx_telemetry_archive_objects_key"
    add_index :telemetry_archive_objects,
              [ :telemetry_archive_id, :status ],
              name: "idx_telemetry_archive_objects_manifest_status"
    add_index :telemetry_archives,
              [ :project_id, :status, :source_deleted_at ],
              name: "idx_telemetry_archives_source_cleanup"
    add_check_constraint :telemetry_archives,
                         "status IN ('pending', 'uploading', 'verifying', 'completed', 'failed', 'restoring', 'restored', 'deleting', 'deleted')",
                         name: "telemetry_archives_lifecycle_status"
    add_check_constraint :telemetry_archives,
                         "expected_rows >= 0 AND expected_bytes >= 0 AND verified_rows >= 0 AND verified_bytes >= 0 AND retry_count >= 0",
                         name: "telemetry_archives_lifecycle_counts"
    add_check_constraint :telemetry_archive_objects,
                         "status IN ('pending', 'uploading', 'uploaded', 'verifying', 'verified', 'failed', 'deleted')",
                         name: "telemetry_archive_objects_status"
    add_check_constraint :telemetry_archive_objects,
                         "expected_rows >= 0 AND expected_bytes >= 0 AND verified_rows >= 0 AND verified_bytes >= 0 AND attempts >= 0",
                         name: "telemetry_archive_objects_counts"
    add_check_constraint :telemetry_archive_objects,
                         "source_min_id <= source_max_id",
                         name: "telemetry_archive_objects_source_range"
  end
end

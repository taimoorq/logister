# frozen_string_literal: true

class CreateProjectPurgeLedgers < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :purge_requested_at, :datetime
    add_index :projects, :purge_requested_at, where: "purge_requested_at IS NOT NULL"

    create_table :project_purges do |table|
      table.references :project,
                       null: true,
                       foreign_key: { on_delete: :nullify },
                       index: false
      table.references :requested_by,
                       null: true,
                       foreign_key: { to_table: :users, on_delete: :nullify },
                       index: false
      table.uuid :project_uuid, null: false
      table.bigint :source_project_id, null: false
      table.string :project_name, null: false
      table.string :idempotency_key, null: false
      table.string :status, null: false, default: "requested"
      table.string :current_step
      table.integer :attempts, null: false, default: 0
      table.datetime :requested_at, null: false
      table.datetime :tombstoned_at
      table.datetime :started_at
      table.datetime :completed_at
      table.datetime :failed_at
      table.datetime :last_error_at
      table.string :last_error_class
      table.text :last_error_message
      table.jsonb :configuration_snapshot, null: false, default: {}
      table.jsonb :audit_log, null: false, default: []
      table.integer :lock_version, null: false, default: 0
      table.timestamps
    end

    add_index :project_purges, :idempotency_key, unique: true
    add_index :project_purges, :project_id
    add_index :project_purges, :project_uuid
    add_index :project_purges, :source_project_id
    add_index :project_purges, [ :status, :created_at ]
    add_index :project_purges, :requested_by_id

    create_table :project_purge_steps do |table|
      table.references :project_purge,
                       null: false,
                       foreign_key: { on_delete: :cascade },
                       index: false
      table.string :store_name, null: false
      table.string :status, null: false, default: "pending"
      table.integer :position, null: false
      table.integer :attempts, null: false, default: 0
      table.datetime :started_at
      table.datetime :completed_at
      table.datetime :failed_at
      table.datetime :last_error_at
      table.string :last_error_class
      table.text :last_error_message
      table.jsonb :result, null: false, default: {}
      table.timestamps
    end

    add_index :project_purge_steps,
              [ :project_purge_id, :store_name ],
              unique: true,
              name: "idx_project_purge_steps_ledger_store"
    add_index :project_purge_steps,
              [ :project_purge_id, :position ],
              unique: true,
              name: "idx_project_purge_steps_ledger_position"
    add_index :project_purge_steps,
              [ :status, :updated_at ],
              name: "idx_project_purge_steps_status_updated"
    add_check_constraint :project_purges,
                         "status IN ('requested', 'tombstoned', 'running', 'awaiting_external', 'verifying', 'completed', 'failed')",
                         name: "project_purges_status"
    add_check_constraint :project_purges,
                         "source_project_id > 0 AND attempts >= 0",
                         name: "project_purges_attempts"
    add_check_constraint :project_purge_steps,
                         "store_name IN ('archives', 'postgresql', 'clickhouse', 'redis')",
                         name: "project_purge_steps_store"
    add_check_constraint :project_purge_steps,
                         <<~SQL.squish,
                           (store_name = 'archives' AND position = 0) OR
                           (store_name = 'clickhouse' AND position = 1) OR
                           (store_name = 'postgresql' AND position = 2) OR
                           (store_name = 'redis' AND position = 3)
                         SQL
                         name: "project_purge_steps_store_position"
    add_check_constraint :project_purge_steps,
                         "status IN ('pending', 'running', 'awaiting_external', 'completed', 'skipped', 'failed')",
                         name: "project_purge_steps_status"
    add_check_constraint :project_purge_steps,
                         "position >= 0 AND attempts >= 0",
                         name: "project_purge_steps_counts"
  end
end

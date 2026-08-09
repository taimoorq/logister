# frozen_string_literal: true

class CreateTelemetryAcceptanceLedger < ActiveRecord::Migration[8.1]
  def change
    create_table :telemetry_idempotency_keys do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.uuid :client_identifier, null: false
      t.string :signal, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.datetime :recorded_at, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :telemetry_idempotency_keys,
      [ :project_id, :client_identifier ],
      unique: true,
      name: "idx_telemetry_idempotency_project_client"
    add_index :telemetry_idempotency_keys, :expires_at
    add_index :telemetry_idempotency_keys,
      [ :record_type, :record_id, :recorded_at ],
      name: "idx_telemetry_idempotency_record"

    create_table :telemetry_outbox_events do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :telemetry_idempotency_key,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: { unique: true, name: "idx_telemetry_outbox_idempotency" }
      t.uuid :client_identifier, null: false
      t.string :signal, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.datetime :recorded_at, null: false
      t.datetime :accepted_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :telemetry_outbox_events, :uuid, unique: true
    add_index :telemetry_outbox_events,
      [ :project_id, :signal, :recorded_at ],
      name: "idx_telemetry_outbox_project_signal_time"
    add_index :telemetry_outbox_events,
      [ :record_type, :record_id, :recorded_at ],
      name: "idx_telemetry_outbox_record"

    create_table :telemetry_deliveries do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :telemetry_outbox_event, null: false, foreign_key: { on_delete: :cascade }
      t.string :destination, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :available_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :leased_at
      t.datetime :lease_expires_at
      t.uuid :lease_token
      t.string :batch_key
      t.datetime :completed_at
      t.datetime :terminal_failed_at
      t.datetime :last_error_at
      t.string :last_error_class
      t.text :last_error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :telemetry_deliveries, :uuid, unique: true
    add_index :telemetry_deliveries,
      [ :telemetry_outbox_event_id, :destination ],
      unique: true,
      name: "idx_telemetry_deliveries_intent"
    add_index :telemetry_deliveries,
      [ :status, :available_at, :id ],
      name: "idx_telemetry_deliveries_due"
    add_index :telemetry_deliveries,
      [ :status, :lease_expires_at ],
      name: "idx_telemetry_deliveries_stale_leases"
    add_index :telemetry_deliveries,
      [ :project_id, :destination, :status ],
      name: "idx_telemetry_deliveries_project_status"
    add_index :telemetry_deliveries, :batch_key

    add_check_constraint :telemetry_deliveries,
      "attempts >= 0",
      name: "telemetry_deliveries_attempts_nonnegative"
  end
end

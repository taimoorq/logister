# frozen_string_literal: true

class CreateTelemetryProjectionBatches < ActiveRecord::Migration[8.1]
  def up
    create_table :telemetry_projection_batches do |t|
      t.references :project, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :destination, null: false
      t.string :batch_key, null: false
      t.bigint :delivery_ids, array: true, null: false
      t.binary :compressed_payload, null: false
      t.string :payload_sha256, null: false
      t.integer :payload_bytes, null: false
      t.timestamps
    end
    add_index :telemetry_projection_batches, [ :project_id, :destination, :batch_key ],
      unique: true, name: "idx_telemetry_projection_batches_identity"
    add_check_constraint :telemetry_projection_batches,
      "cardinality(delivery_ids) BETWEEN 1 AND 200 AND payload_bytes BETWEEN 1 AND 1048577",
      name: "telemetry_projection_batches_bounds"
  end

  def down
    if select_value("SELECT EXISTS (SELECT 1 FROM telemetry_projection_batches LIMIT 1)")
      raise ActiveRecord::IrreversibleMigration, "Drain persisted projection batches before removing their payloads"
    end

    drop_table :telemetry_projection_batches
  end
end

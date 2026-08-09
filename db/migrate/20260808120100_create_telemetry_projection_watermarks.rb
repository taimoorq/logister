# frozen_string_literal: true

class CreateTelemetryProjectionWatermarks < ActiveRecord::Migration[8.1]
  def change
    create_table :telemetry_projection_watermarks do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.string :signal, null: false
      t.string :destination, null: false
      t.datetime :bucket_start_at, null: false
      t.bigint :accepted_count, null: false, default: 0
      t.bigint :delivered_count, null: false, default: 0
      t.bigint :terminal_failure_count, null: false, default: 0
      t.decimal :accepted_checksum, precision: 78, scale: 0, null: false, default: 0
      t.decimal :delivered_checksum, precision: 78, scale: 0, null: false, default: 0
      t.datetime :last_accepted_at
      t.datetime :last_delivered_at
      t.datetime :complete_at

      t.timestamps
    end

    add_index :telemetry_projection_watermarks,
      [ :project_id, :signal, :destination, :bucket_start_at ],
      unique: true,
      name: "idx_telemetry_watermarks_bucket"
    add_index :telemetry_projection_watermarks,
      [ :destination, :bucket_start_at ],
      name: "idx_telemetry_watermarks_destination_time"

    add_check_constraint :telemetry_projection_watermarks,
      "accepted_count >= 0 AND delivered_count >= 0 AND terminal_failure_count >= 0",
      name: "telemetry_watermark_counts_nonnegative"
  end
end

# frozen_string_literal: true

class HardenExternalStorageLifecycle < ActiveRecord::Migration[8.1]
  def change
    change_table :telemetry_archive_objects, bulk: true do |table|
      table.string :storage_generation
      table.jsonb :storage_locator, null: false, default: {}
      table.string :object_version_id
    end

    add_index :telemetry_archive_objects, :storage_generation,
              name: "idx_archive_objects_storage_generation"

    create_table :telemetry_store_generations do |table|
      table.string :store_kind, null: false
      table.string :generation_id, null: false
      table.jsonb :locator, null: false, default: {}
      table.datetime :first_seen_at, null: false
      table.datetime :last_seen_at, null: false
      table.datetime :retired_at
      table.timestamps
    end
    add_index :telemetry_store_generations,
              [ :store_kind, :generation_id ],
              unique: true,
              name: "idx_telemetry_store_generations_logical_key"
    add_index :telemetry_store_generations, [ :store_kind, :last_seen_at ]
  end
end

# frozen_string_literal: true

class CreateAppleSymbolArtifacts < ActiveRecord::Migration[8.1]
  def change
    create_table :apple_symbol_artifacts do |table|
      table.string :uuid, null: false
      table.references :project, null: false, foreign_key: true
      table.references :uploaded_by, foreign_key: { to_table: :users }
      table.string :app_identifier, null: false
      table.string :version_name
      table.string :version_code, null: false
      table.string :release
      table.string :binary_uuid, null: false
      table.string :architecture, null: false
      table.string :checksum_sha256, null: false
      table.bigint :byte_size, null: false
      table.string :filename, null: false
      table.string :content_type
      table.string :storage_key, null: false
      table.string :status, null: false, default: "uploaded"
      table.text :processing_error
      table.jsonb :metadata, null: false, default: {}
      table.datetime :processed_at
      table.datetime :expires_at
      table.timestamps

      table.index :uuid, unique: true
      table.index [ :project_id, :binary_uuid, :architecture, :checksum_sha256 ],
                  unique: true,
                  name: "idx_apple_symbols_identity_checksum"
      table.index [ :project_id, :version_code, :status ], name: "idx_apple_symbols_build_status"
      table.index [ :project_id, :status, :created_at ], name: "idx_apple_symbols_status_created"
    end
  end
end

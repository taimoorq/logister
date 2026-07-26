# frozen_string_literal: true

class CreateAndroidMappingFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :android_mapping_files do |table|
      table.references :project, null: false, foreign_key: true
      table.references :uploaded_by, foreign_key: { to_table: :users }, null: true
      table.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      table.string :package_name, null: false
      table.string :version_name
      table.string :version_code, null: false
      table.string :release
      table.string :checksum_sha256, null: false
      table.bigint :byte_size, null: false
      table.binary :content, null: false
      table.jsonb :metadata, null: false, default: {}
      table.timestamps

      table.index :uuid, unique: true
      table.index [ :project_id, :package_name, :version_code ], unique: true, name: "idx_android_mappings_release_identity"
      table.index [ :project_id, :created_at ]
    end
  end
end

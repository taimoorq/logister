class CreateMobileEventEnrichments < ActiveRecord::Migration[8.0]
  def change
    create_table :mobile_event_enrichments do |table|
      table.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      table.references :project, null: false, foreign_key: true
      table.uuid :event_uuid, null: false
      table.datetime :event_occurred_at, null: false
      table.string :platform, null: false
      table.string :kind, null: false
      table.string :status, null: false
      table.string :input_sha256, null: false
      table.string :artifact_type
      table.uuid :artifact_uuid
      table.string :artifact_checksum_sha256
      table.string :tool_name, null: false
      table.string :tool_version, null: false
      table.jsonb :data, null: false, default: {}
      table.text :processing_error
      table.datetime :processed_at, null: false
      table.timestamps

      table.index :uuid, unique: true
      table.index [ :project_id, :event_uuid, :kind ], unique: true, name: "idx_mobile_enrichments_event_kind"
      table.index [ :project_id, :platform, :kind, :status ], name: "idx_mobile_enrichments_status"
      table.index [ :project_id, :artifact_uuid ], name: "idx_mobile_enrichments_artifact"
    end
  end
end

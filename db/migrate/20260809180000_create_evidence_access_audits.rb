# frozen_string_literal: true

class CreateEvidenceAccessAudits < ActiveRecord::Migration[8.1]
  def change
    create_table :evidence_access_audits do |table|
      table.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      table.references :project, null: false, foreign_key: true
      table.references :user, null: false, foreign_key: true
      table.string :ingest_event_uuid, null: false
      table.datetime :ingest_event_occurred_at, null: false
      table.string :action, null: false
      table.string :reason, null: false
      table.jsonb :request_metadata, null: false, default: {}
      table.timestamps

      table.index :uuid, unique: true
      table.index [ :project_id, :created_at ], name: "idx_evidence_access_project_created"
      table.index [ :project_id, :ingest_event_uuid, :created_at ], name: "idx_evidence_access_event_created"
    end
  end
end

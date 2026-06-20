class CreateMobileIngestTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :mobile_ingest_tokens do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :project, null: false, foreign_key: true
      t.references :api_key, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :platform, null: false
      t.string :service, null: false
      t.string :environment, null: false
      t.string :release
      t.string :session_id
      t.jsonb :allowed_event_types, null: false, default: []
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :mobile_ingest_tokens, :uuid, unique: true
    add_index :mobile_ingest_tokens, :token_digest, unique: true
    add_index :mobile_ingest_tokens, [ :project_id, :expires_at ]
    add_index :mobile_ingest_tokens, [ :api_key_id, :expires_at ]
  end
end

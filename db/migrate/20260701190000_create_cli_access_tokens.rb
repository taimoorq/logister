# frozen_string_literal: true

class CreateCliAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :cli_access_tokens do |t|
      t.uuid :uuid, null: false, default: "gen_random_uuid()"
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.jsonb :scopes, null: false, default: []
      t.jsonb :allowed_project_ids, null: false, default: []
      t.boolean :all_projects, null: false, default: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :cli_access_tokens, :uuid, unique: true
    add_index :cli_access_tokens, :token_digest, unique: true
    add_index :cli_access_tokens, [ :user_id, :expires_at ]
    add_index :cli_access_tokens, [ :user_id, :revoked_at ]
  end
end

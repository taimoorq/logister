class CreateGithubInstallations < ActiveRecord::Migration[8.1]
  def change
    create_table :github_installations do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.bigint :installation_id, null: false
      t.string :account_login, null: false
      t.string :account_type
      t.string :repository_selection
      t.boolean :active, null: false, default: true
      t.datetime :suspended_at
      t.references :installed_by, foreign_key: { to_table: :users }
      t.jsonb :permissions, null: false, default: {}
      t.jsonb :events, null: false, default: []
      t.timestamps
    end

    add_index :github_installations, :uuid, unique: true
    add_index :github_installations, :installation_id, unique: true
    add_index :github_installations, :account_login
  end
end

class CreateGithubRepositories < ActiveRecord::Migration[8.1]
  def change
    create_table :github_repositories do |t|
      t.references :github_installation, null: false, foreign_key: true
      t.bigint :external_id, null: false
      t.string :full_name, null: false
      t.string :owner_name, null: false
      t.string :repo_name, null: false
      t.string :default_branch
      t.string :html_url
      t.boolean :private, null: false, default: true
      t.boolean :archived, null: false, default: false
      t.boolean :active, null: false, default: true
      t.jsonb :permissions, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :github_repositories, :external_id, unique: true
    add_index :github_repositories, :full_name
    add_index :github_repositories, [ :github_installation_id, :active ]
  end
end

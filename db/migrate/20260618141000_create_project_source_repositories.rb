class CreateProjectSourceRepositories < ActiveRecord::Migration[8.1]
  def change
    create_table :project_source_repositories do |t|
      t.references :project, null: false, foreign_key: true
      t.references :github_installation, foreign_key: true
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :provider, null: false, default: "github"
      t.bigint :external_id
      t.string :full_name, null: false
      t.string :owner_name, null: false
      t.string :repo_name, null: false
      t.string :default_branch
      t.string :runtime_root
      t.string :source_root
      t.boolean :enabled, null: false, default: true
      t.datetime :last_synced_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :project_source_repositories, :uuid, unique: true
    add_index :project_source_repositories, [ :project_id, :provider, :full_name ], unique: true
    add_index :project_source_repositories, [ :provider, :external_id ], where: "external_id IS NOT NULL"
    add_index :project_source_repositories, [ :project_id, :enabled ]
  end
end

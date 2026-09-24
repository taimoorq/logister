class CreateProjectLinks < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :cross_project_correlations_enabled, :boolean, default: false, null: false
    create_table :project_links do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :source_project, null: false, foreign_key: { to_table: :projects, on_delete: :cascade }
      t.references :target_project, null: false, foreign_key: { to_table: :projects, on_delete: :cascade }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :relation, null: false, default: "calls"
      t.jsonb :environment_pairs, null: false, default: []
      t.timestamps
    end
    add_index :project_links, :uuid, unique: true
    add_index :project_links, [ :source_project_id, :target_project_id, :relation ], unique: true, name: "index_project_links_unique_pair"
    add_check_constraint :project_links, "source_project_id <> target_project_id", name: "project_links_distinct_projects"
    add_check_constraint :project_links, "relation = 'calls'", name: "project_links_known_relation"
    create_table :project_link_audits do |t|
      t.references :source_project, null: false, foreign_key: { to_table: :projects, on_delete: :cascade }
      t.references :target_project, null: false, foreign_key: { to_table: :projects, on_delete: :cascade }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :action, null: false
      t.jsonb :environment_pairs, null: false, default: []
      t.datetime :created_at, null: false
    end
  end
end

# frozen_string_literal: true

class CreateErrorGroupExternalLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :error_group_external_links do |t|
      t.string :uuid, null: false
      t.references :project, null: false, foreign_key: true
      t.references :error_group, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :provider, null: false, default: "github"
      t.string :link_type, null: false, default: "issue"
      t.string :url, null: false
      t.string :title
      t.string :repository_full_name
      t.string :external_id
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :error_group_external_links, :uuid, unique: true
    add_index :error_group_external_links, [ :error_group_id, :url ], unique: true
    add_index :error_group_external_links, [ :project_id, :provider, :link_type ]
  end
end

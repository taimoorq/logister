# frozen_string_literal: true

class CreateProjectDeployments < ActiveRecord::Migration[8.1]
  def change
    create_table :project_deployments do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :project, null: false, foreign_key: true
      t.references :project_source_repository, foreign_key: true
      t.references :github_repository, foreign_key: true
      t.string :provider, null: false, default: "github"
      t.string :repository_full_name, null: false
      t.string :environment, null: false, default: "production"
      t.string :release, null: false
      t.string :commit_sha, null: false
      t.string :branch
      t.datetime :deployed_at
      t.string :source, null: false, default: "api"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :project_deployments, :uuid, unique: true
    add_index :project_deployments,
              [ :project_id, :repository_full_name, :environment, :release ],
              unique: true,
              name: "index_project_deployments_on_project_repo_env_release"
    add_index :project_deployments, [ :project_id, :release, :environment ]
    add_index :project_deployments, [ :project_id, :commit_sha ]
  end
end

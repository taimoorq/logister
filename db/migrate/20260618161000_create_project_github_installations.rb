# frozen_string_literal: true

class CreateProjectGithubInstallations < ActiveRecord::Migration[8.1]
  def up
    create_table :project_github_installations do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :project, null: false, foreign_key: true
      t.references :github_installation, null: false, foreign_key: true
      t.references :linked_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :project_github_installations, :uuid, unique: true
    add_index :project_github_installations,
              [ :project_id, :github_installation_id ],
              unique: true,
              name: "idx_project_github_installations_project_installation"

    backfill_project_links_from_source_repositories
  end

  def down
    drop_table :project_github_installations
  end

  private

  def backfill_project_links_from_source_repositories
    execute <<~SQL.squish
      INSERT INTO project_github_installations (
        uuid,
        project_id,
        github_installation_id,
        created_at,
        updated_at
      )
      SELECT gen_random_uuid(),
             source_repositories.project_id,
             source_repositories.github_installation_id,
             CURRENT_TIMESTAMP,
             CURRENT_TIMESTAMP
      FROM (
        SELECT project_id, github_installation_id
        FROM project_source_repositories
        WHERE github_installation_id IS NOT NULL
        UNION
        SELECT psr.project_id, gr.github_installation_id
        FROM project_source_repositories psr
        INNER JOIN github_repositories gr ON gr.id = psr.github_repository_id
        WHERE psr.github_repository_id IS NOT NULL
      ) source_repositories
      ON CONFLICT (project_id, github_installation_id) DO NOTHING
    SQL
  end
end

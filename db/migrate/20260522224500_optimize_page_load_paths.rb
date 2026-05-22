class OptimizePageLoadPaths < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :projects,
              [ :user_id, :archived_at, :name ],
              name: "idx_projects_user_archived_name",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :projects,
              [ :user_id, :archived_at, :created_at ],
              order: { created_at: :desc },
              name: "idx_projects_user_archived_created_at",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :project_memberships,
              [ :user_id, :project_id ],
              name: "idx_project_memberships_user_project",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :api_keys,
              [ :project_id, :created_at ],
              order: { created_at: :desc },
              name: "idx_api_keys_project_created_at",
              algorithm: :concurrently,
              if_not_exists: true
  end
end

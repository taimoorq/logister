class AddArchivedAtToProjects < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :projects, :archived_at, :datetime
    add_index :projects, [ :user_id, :archived_at ],
              name: "idx_projects_user_archived_at",
              algorithm: :concurrently,
              if_not_exists: true
  end
end

class AddAssignmentToErrorGroups < ActiveRecord::Migration[8.1]
  def change
    add_reference :error_groups, :assigned_user, foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :error_groups, :assigned_by_user, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :error_groups, :assigned_at, :datetime

    add_index :error_groups,
      [ :project_id, :assigned_user_id, :status, :last_seen_at ],
      order: { last_seen_at: :desc },
      name: "idx_error_groups_project_assignee_status_last_seen"

    add_index :error_groups,
      [ :project_id, :status, :assigned_user_id, :last_seen_at ],
      order: { last_seen_at: :desc },
      name: "idx_error_groups_project_status_assignee_last_seen"
  end
end

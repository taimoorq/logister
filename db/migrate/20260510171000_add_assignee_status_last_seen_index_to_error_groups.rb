class AddAssigneeStatusLastSeenIndexToErrorGroups < ActiveRecord::Migration[8.1]
  def change
    add_index :error_groups,
              [ :assigned_user_id, :status, :last_seen_at ],
              name: "idx_error_groups_assignee_status_last_seen",
              order: { last_seen_at: :desc },
              if_not_exists: true
  end
end

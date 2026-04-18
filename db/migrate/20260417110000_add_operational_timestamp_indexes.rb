class AddOperationalTimestampIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :check_in_monitors, [ :project_id, :last_check_in_at ], name: "index_check_in_monitors_on_project_id_and_last_check_in_at"
    add_index :error_groups, [ :project_id, :first_seen_at ], name: "index_error_groups_on_project_id_and_first_seen_at"
  end
end

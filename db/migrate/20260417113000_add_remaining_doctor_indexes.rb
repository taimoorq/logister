class AddRemainingDoctorIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :api_keys, :last_used_at
    add_index :api_keys, :revoked_at
    add_index :check_in_monitors, :last_error_at
    add_index :error_groups, :archived_at
    add_index :error_groups, :ignored_at
    add_index :error_groups, :last_reopened_at
    add_index :error_groups, :resolved_at
    add_index :users, :confirmation_sent_at
    add_index :users, :confirmed_at
    add_index :users, :remember_created_at
    add_index :users, :reset_password_sent_at
  end
end

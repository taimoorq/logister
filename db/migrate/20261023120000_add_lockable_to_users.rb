# frozen_string_literal: true

# Devise :lockable state. Existing accounts start unlocked with no failures.
class AddLockableToUsers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :users, :failed_attempts, :integer, default: 0, null: false
    add_column :users, :unlock_token, :string
    add_column :users, :locked_at, :datetime
    add_index :users, :unlock_token, unique: true, algorithm: :concurrently
  end
end

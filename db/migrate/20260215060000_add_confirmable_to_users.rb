# frozen_string_literal: true

class AddConfirmableToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :confirmation_token, :string unless column_exists?(:users, :confirmation_token)
    add_column :users, :confirmed_at, :datetime unless column_exists?(:users, :confirmed_at)
    add_column :users, :confirmation_sent_at, :datetime unless column_exists?(:users, :confirmation_sent_at)
    add_column :users, :unconfirmed_email, :string unless column_exists?(:users, :unconfirmed_email)

    add_index :users, :confirmation_token, unique: true unless index_exists?(:users, :confirmation_token)

    execute <<~SQL
      UPDATE users
      SET confirmed_at = CURRENT_TIMESTAMP
      WHERE confirmed_at IS NULL
    SQL
  end

  def down
    remove_index :users, :confirmation_token if index_exists?(:users, :confirmation_token)

    remove_column :users, :unconfirmed_email if column_exists?(:users, :unconfirmed_email)
    remove_column :users, :confirmation_sent_at if column_exists?(:users, :confirmation_sent_at)
    remove_column :users, :confirmed_at if column_exists?(:users, :confirmed_at)
    remove_column :users, :confirmation_token if column_exists?(:users, :confirmation_token)
  end
end
